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

interface ISwap {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256);
}

contract Undesk {
    string public constant name = "Undesk";
}
