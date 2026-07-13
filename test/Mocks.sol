// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, IFeed, ISwap} from "../src/Undesk.sol";

contract Token is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public immutable decimals;

    constructor(uint8 d) {
        decimals = d;
    }

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        if (f != msg.sender) allowance[f][msg.sender] -= v;
        balanceOf[f] -= v;
        balanceOf[t] += v;
        return true;
    }
}


