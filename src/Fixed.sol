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

    /// Square root of a 1e18 number, Babylonian, lifted to 1e36 first.
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 n = x * 1e18;
        y = n;
        uint256 z = n / 2 + 1;
        while (z < y) {
            y = z;
            z = (n / z + z) / 2;
        }
    }

    /// e^x. Argument reduced to |r| <= ln2/2, then a Taylor series.
    function exp(int256 x) internal pure returns (int256) {
        if (x < -42 * ONE) return 0;
        if (x > 88 * ONE) revert Domain();
        int256 k = (x + (x >= 0 ? LN2 / 2 : -LN2 / 2)) / LN2;
        int256 r = x - k * LN2;
        int256 term = ONE;
        int256 sum = ONE;
        for (uint256 i = 1; i <= 12; ++i) {
            term = (term * r) / ONE / int256(i);
            sum += term;
        }
        if (k >= 0) return sum << uint256(k);
        return sum >> uint256(-k);
    }
}
