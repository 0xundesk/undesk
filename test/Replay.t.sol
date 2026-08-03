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

}
