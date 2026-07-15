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

contract StepFeed is IFeed {
    int256 public px;
    uint80 public round;

    function set(int256 p) external {
        px = p;
        ++round;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (round, px, block.timestamp, block.timestamp, round);
    }
}

/// Trades exactly at the feed, so a replay measures the machine and nothing else.
contract MirrorVenue is ISwap {
    IFeed public immutable feed;
    Token public immutable stock;
    Token public immutable cash;

    constructor(IFeed f, Token s, Token c) {
        feed = f;
        stock = s;
        cash = c;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        (, int256 p,,,) = feed.latestRoundData();
        uint256 px = uint256(p);
        if (tokenIn == address(cash)) {
            out = (amountIn * 1e12 * 1e8) / px;
            cash.transferFrom(msg.sender, address(this), amountIn);
            stock.mint(msg.sender, out);
        } else {
            out = (amountIn * px) / 1e8 / 1e12;
            stock.transferFrom(msg.sender, address(this), amountIn);
            cash.mint(msg.sender, out);
        }
        require(out >= minOut, "slip");
        require(tokenOut != address(0));
    }
}

