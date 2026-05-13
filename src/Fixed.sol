// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Fixed
/// @notice The arithmetic this machine needs and the EVM does not have: a
///         logarithm, an exponential, a square root and the bell curve, all in
///         1e18 fixed point, built from integers only.
library Fixed {
    int256 internal constant ONE = 1e18;
    int256 internal constant LN2 = 693147180559945309; // ln 2
    int256 internal constant INV_SQRT_2PI = 398942280401432677; // 1/sqrt(2*pi)

    error Domain();

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = x / 2 + 1;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
}
