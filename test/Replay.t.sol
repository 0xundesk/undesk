// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Undesk, IERC20, IFeed, ISwap} from "../src/Undesk.sol";
import {Fixed} from "../src/Fixed.sol";
import {History} from "./History.sol";
import {Token, StepFeed, MirrorVenue} from "./Mocks.sol";

contract ReplayTest is Test {
    uint256 constant YEAR = 365 days;
    uint256 constant TERM = 30 days;
    uint256 constant SHARES = 100e18;
}
