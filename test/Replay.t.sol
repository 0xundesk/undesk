// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Undesk, IERC20, IFeed, ISwap} from "../src/Undesk.sol";
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

    struct Ctx {
        uint40 t0;
        uint64 p0;
        uint256 iEnd;
        uint64 vol;
        uint256 prem;
        uint256 id;
        Undesk u;
    }

    function replay(uint256 i0, uint64 band, uint256 bounty) internal returns (Run memory r) {
        Ctx memory c;
        c.t0 = TS[i0];
        c.p0 = PX[i0];
        c.iEnd = i0;
        while (c.iEnd + 1 < TS.length && uint256(TS[c.iEnd + 1]) <= uint256(c.t0) + TERM) {
            ++c.iEnd;
        }
        c.vol = volOf(i0, c.iEnd);
        if (c.vol == 0) return r;

        c.u = new Undesk(
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
        c.id = c.u.open(SHARES, c.prem, c.p0, uint40(uint256(c.t0) + TERM), c.vol, band);
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

}
