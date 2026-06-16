// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BS} from "./BS.sol";

interface IERC20 {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
    function approve(address s, uint256 v) external returns (bool);
}

interface IFeed {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

/// Swaps one leg for the other. The vault always states the worst price it
/// will accept, computed from the feed, so a bad venue reverts instead of
/// quietly eating the position.
interface ISwap {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256);
}

/// @title Undesk
/// @notice An option nobody wrote. You put in stock. The vault slides between
///         stock and cash at every price the chain publishes, so that at the
///         end it holds what "the stock, but never below the floor" would have
///         paid. There is no writer, no counterparty and no promise to trust:
///         the payoff is manufactured out of your own two assets.
contract Undesk {
    string public constant name = "Undesk";

    IERC20 public immutable stock;
    IERC20 public immutable cashToken;
    IFeed public immutable feed;
    ISwap public immutable venue;

    uint256 internal constant SHARE = 1e18; // stock decimals
    uint256 internal constant CASH = 1e6; // cash decimals
    uint256 internal constant PX = 1e8; // feed decimals
    int256 internal constant ONE = 1e18;
    uint256 internal constant YEAR = 365 days;

    uint256 public constant MAX_SLIP_BPS = 100; // 1% away from the feed, or revert

    /// Paid to whoever pushes the button, in cash units. It has to beat the gas
    /// of this chain, about 0.60 dollars, or nobody pushes it. It comes out of
    /// the vault, so it is part of what the floor really costs.
    uint256 public immutable bounty;

    struct Vault {
        address owner;
        uint96 floor; // 1e8, the line the value must not end below
        uint40 expiry;
        uint64 vol; // 1e18 annualised
        uint64 band; // 1e18, how far the weight may drift before a rebalance
        uint256 shares; // 1e18
        uint256 cash; // 1e6
        uint256 rebalances;
        bool closed;
    }

    Vault[] public vaults;

    event Opened(uint256 indexed id, address indexed owner, uint256 shares, uint96 floor, uint40 expiry);
    event Rebalanced(uint256 indexed id, int256 price, int256 target, uint256 shares, uint256 cash, address by);
    event Closed(uint256 indexed id, uint256 shares, uint256 cash, int256 price);

    error Bad();
    error NotOwner();
    error Live();
    error Done();
    error NoDrift();

    constructor(IERC20 stock_, IERC20 cash_, IFeed feed_, ISwap venue_, uint256 bounty_) {
        bounty = bounty_;
        stock = stock_;
        cashToken = cash_;
        feed = feed_;
        venue = venue_;
    }

    function count() external view returns (uint256) {
        return vaults.length;
    }

    /// What the floor costs, in cash units, for this many shares. This is the
    /// textbook put price and nobody receives it: it is the raw material the
    /// vault spends manufacturing the payoff.
    function quote(uint256 shares_, uint96 floor_, uint40 expiry_, uint64 vol_) public view returns (uint256) {
        (, int256 p,,,) = feed.latestRoundData();
        int256 t = int256((uint256(expiry_) - block.timestamp) * 1e18 / YEAR);
        int256 prem =
            BS.putPrice(int256(uint256(p)) * 1e10, int256(uint256(floor_)) * 1e10, int256(uint256(vol_)), t);
        if (prem < 0) prem = 0;
        return (uint256(prem) * shares_) / SHARE / 1e12;
    }

    /// Put in stock and the cash the floor costs. From here the vault holds
    /// "the stock, but never below the floor", and no one wrote it.
    function open(uint256 shares_, uint256 cash_, uint96 floor_, uint40 expiry_, uint64 vol_, uint64 band_)
        external
        returns (uint256 id)
    {
        if (shares_ == 0 || floor_ == 0 || expiry_ <= block.timestamp || vol_ == 0) revert Bad();
        stock.transferFrom(msg.sender, address(this), shares_);
        if (cash_ > 0) cashToken.transferFrom(msg.sender, address(this), cash_);
        id = vaults.length;
        vaults.push(
            Vault(msg.sender, floor_, expiry_, vol_, band_ == 0 ? uint64(0.02e18) : band_, shares_, cash_, 0, false)
        );
        emit Opened(id, msg.sender, shares_, floor_, expiry_);
        _move(id);
    }

}
