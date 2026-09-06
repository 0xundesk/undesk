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

/// @title Hodi
/// @notice Your high becomes your floor. You put in stock. The vault slides
///         between stock and cash at every price the chain publishes, holding
///         a floor under the position, and when the price climbs it drags the
///         floor up behind it. A hodi turns one way: the floor rises, locks,
///         and never comes back down. There is no writer, no counterparty and
///         no promise to trust: the payoff is manufactured out of your own two
///         assets, and every click of the hodi is a public transaction.
contract Hodi {
    string public constant name = "Hodi";

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
    uint256 public constant RUNWAY = 7 days; // a click needs room: no new floor it cannot defend
    uint256 public constant MAX_AGE = 5 days; // a feed that has stopped printing prices nothing

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
        uint64 lift; // 1e18, how much higher a candidate floor must be to click
        uint256 shares; // 1e18
        uint256 cash; // 1e6
        uint256 locked; // 1e18 cash value, the guarantee. Only ever rises.
        uint256 rebalances;
        uint256 lifts;
        bool closed;
    }

    Vault[] public vaults;

    event Opened(uint256 indexed id, address indexed owner, uint256 shares, uint96 floor, uint40 expiry);
    event Rebalanced(uint256 indexed id, int256 price, int256 target, uint256 shares, uint256 cash, address by);
    event Closed(uint256 indexed id, uint256 shares, uint256 cash, int256 price);
    event Lifted(uint256 indexed id, uint96 floor, uint256 locked, address by);

    error Bad();
    error NotOwner();
    error Live();
    error Done();
    error NoDrift();
    error Stale();
    error Fail();

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

    /// The feed's price, refused when it is nonsense or has stopped printing.
    /// Everything that decides or prices a trade reads through here; close()
    /// does not, so a dead feed can never hold the assets hostage.
    function _fresh() internal view returns (uint256) {
        (, int256 p,, uint256 at,) = feed.latestRoundData();
        if (p <= 0 || block.timestamp > at + MAX_AGE) revert Stale();
        return uint256(p);
    }

    function _take(IERC20 t, uint256 v) internal {
        if (!t.transferFrom(msg.sender, address(this), v)) revert Fail();
    }

    function _pay(IERC20 t, address to, uint256 v) internal {
        if (!t.transfer(to, v)) revert Fail();
    }

    /// What the floor costs, in cash units, for this many shares. This is the
    /// textbook put price and nobody receives it: it is the raw material the
    /// vault spends manufacturing the payoff.
    function quote(uint256 shares_, uint96 floor_, uint40 expiry_, uint64 vol_) public view returns (uint256) {
        int256 p = int256(_fresh());
        int256 t = int256((uint256(expiry_) - block.timestamp) * 1e18 / YEAR);
        int256 prem = BS.putPrice(p * 1e10, int256(uint256(floor_)) * 1e10, int256(uint256(vol_)), t);
        if (prem < 0) prem = 0;
        return (uint256(prem) * shares_) / SHARE / 1e12;
    }

    /// Put in stock and the cash the floor costs. From here the vault holds
    /// "the stock, but never below the floor", and when the stock climbs, the
    /// floor climbs after it and locks.
    function open(uint256 shares_, uint256 cash_, uint96 floor_, uint40 expiry_, uint64 vol_, uint64 band_, uint64 lift_)
        external
        returns (uint256 id)
    {
        if (shares_ == 0 || floor_ == 0 || expiry_ <= block.timestamp || vol_ == 0) revert Bad();
        _take(stock, shares_);
        if (cash_ > 0) _take(cashToken, cash_);
        id = vaults.length;
        vaults.push(
            Vault(
                msg.sender,
                floor_,
                expiry_,
                vol_,
                band_ == 0 ? uint64(0.02e18) : band_,
                lift_ == 0 ? uint64(0.02e18) : lift_,
                shares_,
                cash_,
                (shares_ * uint256(floor_)) / PX,
                0,
                0,
                false
            )
        );
        emit Opened(id, msg.sender, shares_, floor_, expiry_);
        _move(id);
    }

    /// Where the floor could move today. If re-striking at the current price
    /// would guarantee more cash value than the vault already has locked, by
    /// at least the vault's lift, the hodi has a click waiting. Returns the
    /// candidate floor and its guaranteed value, or two zeros.
    function click(uint256 id) public view returns (uint96 newFloor, uint256 newLocked) {
        Vault storage v = vaults[id];
        if (v.closed || uint256(v.expiry) < block.timestamp + RUNWAY) return (0, 0);
        uint256 px = _fresh();
        int256 t = int256((uint256(v.expiry) - block.timestamp) * 1e18 / YEAR);
        int256 atm = BS.putPrice(int256(px) * 1e10, int256(px) * 1e10, int256(uint256(v.vol)), t);
        if (atm < 0) atm = 0;
        // triple the textbook cost: the hedge that manufactures the new floor
        // has its own slack, and the click must not promise more than the
        // manufacturing line can deliver in a fast tape.
        uint256 need = px * 1e10 + 2 * uint256(atm);
        uint256 cand = (value(id) * px * 1e10) / need;
        if (cand >= v.locked + (v.locked * v.lift) / 1e18) return (uint96(px), cand);
        return (0, 0);
    }

    /// The share of the vault that belongs in stock right now.
    function target(uint256 id) public view returns (int256) {
        Vault storage v = vaults[id];
        int256 p = int256(_fresh());
        int256 t = v.expiry <= block.timestamp ? int256(0) : int256((uint256(v.expiry) - block.timestamp) * 1e18 / YEAR);
        return BS.insuredWeight(p * 1e10, int256(uint256(v.floor)) * 1e10, int256(uint256(v.vol)), t);
    }

    /// The share of the vault that is in stock right now.
    function weight(uint256 id) public view returns (int256) {
        Vault storage v = vaults[id];
        uint256 inStock = (v.shares * _fresh()) / PX; // 1e18 of value
        uint256 total = inStock + v.cash * 1e12;
        if (total == 0) return 0;
        return int256((inStock * uint256(ONE)) / total);
    }

    function value(uint256 id) public view returns (uint256) {
        Vault storage v = vaults[id];
        (, int256 p,,,) = feed.latestRoundData();
        return (v.shares * uint256(p)) / PX + v.cash * 1e12;
    }

    /// Anyone may push the button once the hodi has a click waiting or the
    /// weight has drifted past the band. The caller is paid out of the vault.
    function rebalance(uint256 id) external {
        Vault storage v = vaults[id];
        if (v.closed) revert Done();
        (uint96 nf, uint256 nl) = click(id);
        if (nf != 0) {
            v.floor = nf;
            v.locked = nl;
            unchecked {
                ++v.lifts;
            }
            emit Lifted(id, nf, nl, msg.sender);
        }
        int256 want = target(id);
        int256 have = weight(id);
        int256 gap = want > have ? want - have : have - want;
        if (nf == 0 && gap < int256(uint256(v.band))) revert NoDrift();
        _move(id);
        unchecked {
            ++v.rebalances;
        }
        uint256 fee = bounty > v.cash ? v.cash : bounty;
        if (fee > 0) {
            v.cash -= fee;
            _pay(cashToken, msg.sender, fee);
        }
        emit Rebalanced(id, int256(_fresh()), want, v.shares, v.cash, msg.sender);
    }

    /// After the day named, everything goes back to the owner. What comes back
    /// is the manufactured payoff, not a promise anyone made.
    function close(uint256 id) external {
        Vault storage v = vaults[id];
        if (v.closed) revert Done();
        if (block.timestamp < v.expiry) revert Live();
        v.closed = true;
        uint256 s = v.shares;
        uint256 c = v.cash;
        v.shares = 0;
        v.cash = 0;
        if (s > 0) _pay(stock, v.owner, s);
        if (c > 0) _pay(cashToken, v.owner, c);
        (, int256 p,,,) = feed.latestRoundData();
        emit Closed(id, s, c, p);
    }

    /// Slide to the target weight at the feed's price, refusing any venue that
    /// is more than MAX_SLIP_BPS away from it.
    function _move(uint256 id) internal {
        Vault storage v = vaults[id];
        uint256 px = _fresh();

        uint256 inStock = (v.shares * px) / PX;
        uint256 total = inStock + v.cash * 1e12;
        if (total == 0) return;

        uint256 want = (total * uint256(target(id))) / uint256(ONE);

        if (want > inStock) {
            uint256 buy = want - inStock; // value of stock to buy, 1e18
            uint256 spend = buy / 1e12; // cash units
            if (spend > v.cash) spend = v.cash;
            if (spend == 0) return;
            uint256 minOut = ((spend * 1e12 * PX) / px) * (10_000 - MAX_SLIP_BPS) / 10_000;
            v.cash -= spend;
            cashToken.approve(address(venue), spend);
            uint256 got = venue.swap(address(cashToken), address(stock), spend, minOut);
            v.shares += got;
        } else {
            uint256 sell = inStock - want; // value of stock to sell, 1e18
            uint256 qty = (sell * PX) / px; // stock units
            if (qty > v.shares) qty = v.shares;
            if (qty == 0) return;
            uint256 minOut = ((qty * px) / PX / 1e12) * (10_000 - MAX_SLIP_BPS) / 10_000;
            v.shares -= qty;
            stock.approve(address(venue), qty);
            uint256 got = venue.swap(address(stock), address(cashToken), qty, minOut);
            v.cash += got;
        }
    }
}
