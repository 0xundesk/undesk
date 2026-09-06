// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, ISwap} from "./Undesk.sol";

interface IV3Pool {
    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data)
        external
        returns (int256 amount0, int256 amount1);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title Venue
/// @notice The thinnest possible bridge between the vault and the pool where
///         the two legs actually trade. One pool, both directions, output
///         straight back to whoever asked. The pool may only collect payment
///         while a swap this contract started is in flight.
contract Venue is ISwap {
    IV3Pool public immutable pool;
    address public immutable token0;
    address public immutable token1;

    // one past the ends of the v3 price range: no limit beyond the pool itself
    uint160 internal constant MIN_SQRT = 4295128740;
    uint160 internal constant MAX_SQRT = 1461446703485210103287273052203988822378723970341;

    address internal payerInFlight;

    error WrongPair();
    error PoolOnly();
    error NoSwapInFlight();
    error TooLittleOut();

    constructor(IV3Pool pool_) {
        pool = pool_;
        token0 = pool_.token0();
        token1 = pool_.token1();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        bool zeroForOne = tokenIn == token0 && tokenOut == token1;
        if (!zeroForOne && !(tokenIn == token1 && tokenOut == token0)) revert WrongPair();

        payerInFlight = msg.sender;
        (int256 a0, int256 a1) =
            pool.swap(msg.sender, zeroForOne, int256(amountIn), zeroForOne ? MIN_SQRT : MAX_SQRT, abi.encode(tokenIn));
        payerInFlight = address(0);

        out = uint256(-(zeroForOne ? a1 : a0));
        if (out < minOut) revert TooLittleOut();
    }

    /// The pool calls back for its payment mid-swap. Pay it from the caller
    /// who started the swap, and from nobody else, at no other time.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        if (msg.sender != address(pool)) revert PoolOnly();
        address payer = payerInFlight;
        if (payer == address(0)) revert NoSwapInFlight();
        address tokenIn = abi.decode(data, (address));
        uint256 owed = uint256(amount0Delta > 0 ? amount0Delta : amount1Delta);
        IERC20(tokenIn).transferFrom(payer, address(pool), owed);
    }
}
