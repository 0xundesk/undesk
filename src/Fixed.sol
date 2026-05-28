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

    /// Natural log of a 1e18 number. x = m * 2^k with m in [1,2), then the
    /// atanh series on m, which converges fast because z is at most 1/3.
    function ln(int256 x) internal pure returns (int256) {
        if (x <= 0) revert Domain();
        int256 k;
        int256 m = x;
        while (m >= 2 * ONE) {
            m >>= 1;
            ++k;
        }
        while (m < ONE) {
            m <<= 1;
            --k;
        }
        int256 z = ((m - ONE) * ONE) / (m + ONE);
        int256 z2 = (z * z) / ONE;
        int256 term = z;
        int256 sum = z;
        for (uint256 i = 1; i <= 12; ++i) {
            term = (term * z2) / ONE;
            sum += term / int256(2 * i + 1);
        }
        return 2 * sum + k * LN2;
    }

    /// The bell curve's running total: the probability a standard normal lands
    /// below x. Abramowitz and Stegun 26.2.17, good to about 7.5e-8.
    function ncdf(int256 x) internal pure returns (int256) {
        bool neg = x < 0;
        int256 a = neg ? -x : x;
        if (a > 10 * ONE) return neg ? int256(0) : ONE;

        int256 t = (ONE * ONE) / (ONE + (231641900000000000 * a) / ONE);
        int256 phi = (INV_SQRT_2PI * exp(-(a * a) / ONE / 2)) / ONE;

        int256 poly = 1330274429000000000; // b5, Horner from the top down
        poly = ((poly * t) / ONE) - 1821255978000000000; // b4
        poly = ((poly * t) / ONE) + 1781477937000000000; // b3
        poly = ((poly * t) / ONE) - 356563782000000000; // b2
        poly = ((poly * t) / ONE) + 319381530000000000; // b1
        poly = (poly * t) / ONE;

        int256 upper = (phi * poly) / ONE;
        int256 n = ONE - upper;
        return neg ? ONE - n : n;
    }
}
