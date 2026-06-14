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

    }
