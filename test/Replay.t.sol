// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hodi, IERC20, IFeed, ISwap} from "../src/Hodi.sol";
import {Fixed} from "../src/Fixed.sol";
import {History} from "./History.sol";
import {Token, StepFeed, MirrorVenue} from "./Mocks.sol";

/// The machine, replayed on the prices this chain actually published.
contract ReplayTest is Test {
    uint256 constant YEAR = 365 days;
    uint256 constant TERM = 30 days;
    uint256 constant SHARES = 100e18; // a hundred shares, about 23,000 dollars

    Token stock;
    Token cash;
    StepFeed feed;
    MirrorVenue venue;

    address user = address(0xA11CE);
    address pusher = address(0xB0B);

    uint40[] TS;
    uint64[] PX;

    function setUp() public {
        (uint40[] memory ts, uint64[] memory px) = History.load();
        for (uint256 i = 0; i < ts.length; ++i) {
            TS.push(ts[i]);
            PX.push(px[i]);
        }
        stock = new Token(18);
        cash = new Token(6);
        feed = new StepFeed();
        venue = new MirrorVenue(IFeed(address(feed)), stock, cash);
    }

    /// Annualised volatility of a window, from the prints themselves.
    function volOf(uint256 i0, uint256 i1) internal view returns (uint64) {
        int256 sum;
        int256 sumsq;
        uint256 n;
        for (uint256 i = i0; i + 1 <= i1; ++i) {
            int256 r = Fixed.ln((int256(uint256(PX[i + 1])) * 1e18) / int256(uint256(PX[i])));
            sum += r;
            sumsq += (r * r) / 1e18;
            ++n;
        }
        if (n < 5) return 0;
        int256 mean = sum / int256(n);
        int256 varr = sumsq / int256(n) - (mean * mean) / 1e18;
        if (varr <= 0) return 0;
        uint256 dt = ((uint256(TS[i1]) - uint256(TS[i0])) * 1e18) / n / YEAR;
        int256 sd = int256(Fixed.sqrt(uint256(varr)));
        return uint64(uint256((sd * 1e18) / int256(Fixed.sqrt(dt))));
    }

    struct Run {
        uint256 errBps; // |vault - what the payoff owed| as bps of the premium
        uint256 rebalances;
        uint256 premium;
    }

    Hodi lastU;
    uint256 lastId;

    struct Ctx {
        uint40 t0;
        uint64 p0;
        uint256 iEnd;
        uint64 vol;
        uint256 prem;
        uint256 id;
        Hodi u;
    }

    function replay(uint256 i0, uint64 band, uint256 bounty) internal returns (Run memory r) {
        return replay(i0, band, bounty, type(uint64).max); // the floor stays where it was set
    }

    function replay(uint256 i0, uint64 band, uint256 bounty, uint64 lift) internal returns (Run memory r) {
        Ctx memory c;
        c.t0 = TS[i0];
        c.p0 = PX[i0];
        c.iEnd = i0;
        while (c.iEnd + 1 < TS.length && uint256(TS[c.iEnd + 1]) <= uint256(c.t0) + TERM) {
            ++c.iEnd;
        }
        c.vol = volOf(i0, c.iEnd);
        if (c.vol == 0) return r;

        c.u = new Hodi(
            IERC20(address(stock)), IERC20(address(cash)), IFeed(address(feed)), ISwap(address(venue)), bounty
        );

        vm.warp(c.t0);
        feed.set(int256(uint256(c.p0)));

        c.prem = c.u.quote(SHARES, c.p0, uint40(uint256(c.t0) + TERM), c.vol);
        r.premium = c.prem;

        stock.mint(user, SHARES);
        cash.mint(user, c.prem);
        vm.startPrank(user);
        stock.approve(address(c.u), type(uint256).max);
        cash.approve(address(c.u), type(uint256).max);
        c.id = c.u.open(SHARES, c.prem, c.p0, uint40(uint256(c.t0) + TERM), c.vol, band, lift);
        lastU = c.u;
        lastId = c.id;
        vm.stopPrank();

        for (uint256 i = i0 + 1; i <= c.iEnd; ++i) {
            vm.warp(TS[i]);
            feed.set(int256(uint256(PX[i])));
            vm.prank(pusher);
            try c.u.rebalance(c.id) {
                ++r.rebalances;
            } catch {}
        }

        uint256 pT = uint256(PX[c.iEnd]);
        uint256 owed = (pT > uint256(c.p0) ? pT : uint256(c.p0)) * SHARES / 1e8;
        uint256 got = c.u.value(c.id);
        uint256 diff = got > owed ? got - owed : owed - got;
        r.errBps = c.prem == 0 ? 0 : (diff * 10_000) / (c.prem * 1e12);
    }

    function _median(uint256[] memory a) internal pure returns (uint256) {
        for (uint256 i = 1; i < a.length; ++i) {
            uint256 k = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > k) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = k;
        }
        return a[a.length / 2];
    }

    /// The number this project lives or dies by: how close the manufactured
    /// payoff lands to what the option actually owed, using nothing but the
    /// prices this chain published.
    function test_ReplicationErrorOnRealHistory() public {
        uint256 n = TS.length;
        uint256[] memory errs = new uint256[](12);
        uint256[] memory rebs = new uint256[](12);
        uint256 k;
        for (uint256 i = 0; i < 12; ++i) {
            uint256 i0 = (i * (n - 260)) / 12;
            Run memory r = replay(i0, 0.02e18, 0);
            if (r.premium == 0) continue;
            errs[k] = r.errBps;
            rebs[k] = r.rebalances;
            ++k;
        }
        assembly {
            mstore(errs, k)
            mstore(rebs, k)
        }
        uint256 med = _median(errs);
        emit log_named_uint("windows replayed", k);
        emit log_named_uint("median rebalances per 30 days", _median(rebs));
        emit log_named_decimal_uint("MEDIAN REPLICATION ERROR, % of premium", med, 2);
        assertLt(med, 1000, "must land inside 10% of the premium");
    }

    /// What the floor really costs on this chain: fewer rebalances mean less
    /// gas and more error. The bounty is what the button pusher is paid, and
    /// 1 dollar is roughly the measured fee of a transaction here.
    function test_CostCurve() public {
        uint256 n = TS.length;
        uint64[4] memory bands = [uint64(0), 0.02e18, 0.05e18, 0.10e18];
        emit log_string("band | rebalances | error without the bounty | error paying 1 dollar a push");
        for (uint256 b = 0; b < bands.length; ++b) {
            uint256[] memory free_ = new uint256[](8);
            uint256[] memory paid = new uint256[](8);
            uint256[] memory rebs = new uint256[](8);
            uint256 k;
            for (uint256 i = 0; i < 8; ++i) {
                uint256 i0 = (i * (n - 260)) / 8;
                Run memory a = replay(i0, bands[b], 0);
                Run memory c = replay(i0, bands[b], 1e6);
                if (a.premium == 0) continue;
                free_[k] = a.errBps;
                paid[k] = c.errBps;
                rebs[k] = a.rebalances;
                ++k;
            }
            assembly {
                mstore(free_, k)
                mstore(paid, k)
                mstore(rebs, k)
            }
            emit log_named_uint("band (1e18)", bands[b]);
            emit log_named_uint("  rebalances", _median(rebs));
            emit log_named_decimal_uint("  error %", _median(free_), 2);
            emit log_named_decimal_uint("  error % paying the pusher", _median(paid), 2);
        }
    }

    /// The twist, on the market that actually happened: the floor follows the
    /// price up and never comes back down. Measured over the real prints.
    function test_TheHodiOnRealHistory() public {
        uint256 n = TS.length;
        int256[] memory head = new int256[](12);
        uint256[] memory clicks = new uint256[](12);
        int256[] memory gain = new int256[](12);
        uint256 k;
        uint256 breaches;
        for (uint256 i = 0; i < 12; ++i) {
            uint256 i0 = (i * (n - 260)) / 12;
            Run memory r = replay(i0, 0.02e18, 0, 0.02e18);
            if (r.premium == 0) continue;
            (, uint96 floorF,,,,,,, uint256 locked,, uint256 lifts,) = lastU.vaults(lastId);
            uint256 got = lastU.value(lastId);
            uint64 p0 = PX[i0];
            clicks[k] = lifts;
            gain[k] = int256((uint256(floorF) * 1e18) / uint256(p0)) - 1e18;
            head[k] = int256((got * 1e18) / locked) - 1e18;
            if (got < locked) ++breaches;
            emit log_named_decimal_int("  window headroom", int256((got * 1e18) / locked) - 1e18, 16);
            ++k;
        }
        assembly {
            mstore(head, k)
            mstore(clicks, k)
            mstore(gain, k)
        }
        emit log_named_uint("windows", k);
        emit log_named_uint("median clicks per 30 days", _median(clicks));
        emit log_named_decimal_int("median floor rise over the month", _medianInt(gain), 16);
        emit log_named_decimal_int("median finish above the locked floor", _medianInt(head), 16);
        emit log_named_uint("windows that finished below their locked floor", breaches);
    }

    function _medianInt(int256[] memory a) internal pure returns (int256) {
        for (uint256 i = 1; i < a.length; ++i) {
            int256 x = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > x) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = x;
        }
        return a[a.length / 2];
    }
}
