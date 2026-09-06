// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Ratchet, IERC20, IFeed, ISwap} from "../src/Ratchet.sol";
import {Venue, IV3Pool} from "../src/Venue.sol";

/// Hood Chain mainnet, the NVDA desk.
/// forge script script/Deploy.s.sol --rpc-url hood --broadcast --private-key $KEY
contract Deploy is Script {
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    address constant POOL = 0xd4EB21209C4D6093f80B5b84f5C45cc093EA14a3;

    uint256 constant BOUNTY = 1e6; // one dollar a push, comfortably above the gas

    function run() external {
        vm.startBroadcast();
        Venue venue = new Venue(IV3Pool(POOL));
        Ratchet ratchet = new Ratchet(IERC20(NVDA), IERC20(USDG), IFeed(FEED), ISwap(address(venue)), BOUNTY);
        vm.stopBroadcast();
        console2.log("venue ", address(venue));
        console2.log("ratchet", address(ratchet));
    }
}
