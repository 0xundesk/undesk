// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hodi, IERC20, IFeed, ISwap} from "../src/Hodi.sol";
import {Venue, IV3Pool} from "../src/Venue.sol";

/// The venue and the vault against the real pool, the real tokens and the
/// real feed on a Hood Chain mainnet fork.
/// forge test --match-contract VenueFork --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract VenueForkTest is Test {
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    address constant POOL = 0xd4EB21209C4D6093f80B5b84f5C45cc093EA14a3;
    address constant NVDA_WHALE = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    Venue venue;
    address user = address(0xA11CE);

    function setUp() public {
        // this suite only means something on the real chain
        vm.skip(block.chainid != 4663);
        venue = new Venue(IV3Pool(POOL));
        // stock from the biggest holder on the chain, cash via storage deal
        vm.prank(NVDA_WHALE);
        IERC20(NVDA).transfer(user, 10e18);
        deal(USDG, user, 100_000e6);
    }

    function feedPx() internal view returns (uint256) {
        (, int256 p,,,) = IFeed(FEED).latestRoundData();
        return uint256(p);
    }

    function test_CashToStockAtTheFeed() public {
        uint256 px = feedPx();
        uint256 spend = 1_000e6; // a thousand dollars
        uint256 expect = (spend * 1e12 * 1e8) / px;

        vm.startPrank(user);
        IERC20(USDG).approve(address(venue), spend);
        uint256 out = venue.swap(USDG, NVDA, spend, expect * 98 / 100);
        vm.stopPrank();

        emit log_named_decimal_uint("bought shares", out, 18);
        emit log_named_decimal_uint("feed said", expect, 18);
        assertGt(out, expect * 98 / 100, "worse than 2% off the feed");
        assertLt(out, expect * 102 / 100, "suspiciously better than the feed");
    }

    function test_StockToCashAtTheFeed() public {
        uint256 px = feedPx();
        uint256 qty = 2e18;
        uint256 expect = (qty * px) / 1e8 / 1e12;

        vm.startPrank(user);
        IERC20(NVDA).approve(address(venue), qty);
        uint256 out = venue.swap(NVDA, USDG, qty, expect * 98 / 100);
        vm.stopPrank();

        emit log_named_decimal_uint("sold for", out, 6);
        emit log_named_decimal_uint("feed said", expect, 6);
        assertGt(out, expect * 98 / 100);
    }

    function test_StrangersCannotUseTheCallback() public {
        vm.expectRevert(Venue.PoolOnly.selector);
        venue.uniswapV3SwapCallback(1e6, 0, abi.encode(USDG));

        // even the pool itself gets nothing when no swap is in flight
        vm.prank(POOL);
        vm.expectRevert(Venue.NoSwapInFlight.selector);
        venue.uniswapV3SwapCallback(1e6, 0, abi.encode(USDG));
    }

    /// The whole machine against the whole real world: open a floored
    /// position on real NVDA, watch it take its opening hedge on the real
    /// pool, then close after expiry and get both legs back.
    function test_VaultOnTheRealPool() public {
        Hodi u = new Hodi(IERC20(NVDA), IERC20(USDG), IFeed(FEED), ISwap(address(venue)), 1e6);

        uint96 floor = uint96(feedPx());
        uint40 expiry = uint40(block.timestamp + 30 days);
        uint256 shares = 5e18;
        uint256 prem = u.quote(shares, floor, expiry, 0.42e18);
        emit log_named_decimal_uint("floor costs (USDG)", prem, 6);

        vm.startPrank(user);
        IERC20(NVDA).approve(address(u), shares);
        IERC20(USDG).approve(address(u), prem);
        uint256 id = u.open(shares, prem, floor, expiry, 0.42e18, 0.02e18, type(uint64).max);
        vm.stopPrank();

        int256 want = u.target(id);
        int256 have = u.weight(id);
        emit log_named_decimal_int("target weight", want, 18);
        emit log_named_decimal_int("actual weight after the opening hedge", have, 18);
        int256 gap = want > have ? want - have : have - want;
        assertLt(gap, 0.03e18, "opening hedge missed the target");

        uint256 valueNow = u.value(id);
        uint256 valueIn = (shares * feedPx()) / 1e8 + prem * 1e12;
        emit log_named_decimal_uint("value in", valueIn, 18);
        emit log_named_decimal_uint("value after hedge", valueNow, 18);
        assertGt(valueNow, valueIn * 99 / 100, "the opening hedge cost more than 1%");

        vm.warp(expiry + 1);
        vm.prank(user);
        u.close(id);
        assertGt(IERC20(NVDA).balanceOf(user) + 1, 0);
    }
}
