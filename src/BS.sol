// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixed} from "./Fixed.sol";

/// @title BS
/// @notice What an option is worth, and how much stock you must hold to
///         manufacture it. Rate is zero: the cash leg of this machine is a
///         stablecoin that pays nothing, so pretending otherwise would lie.
library BS {
    int256 internal constant ONE = 1e18;

    /// d1 and d2, the two numbers the whole formula is built from.
    function ds(int256 spot, int256 strike, int256 vol, int256 tYears)
        internal
        pure
        returns (int256 d1, int256 d2)
    {
        int256 sqrtT = int256(Fixed.sqrt(uint256(tYears)));
        int256 vSqrtT = (vol * sqrtT) / ONE;
        int256 lnSK = Fixed.ln((spot * ONE) / strike);
        d1 = ((lnSK + (((vol * vol) / ONE) * tYears) / ONE / 2) * ONE) / vSqrtT;
        d2 = d1 - vSqrtT;
    }

    /// The fraction of one share you must hold to track a call.
    function callDelta(int256 spot, int256 strike, int256 vol, int256 tYears) internal pure returns (int256) {
        if (tYears <= 0) return spot > strike ? ONE : int256(0);
        (int256 d1,) = ds(spot, strike, vol, tYears);
        return Fixed.ncdf(d1);
    }

    function callPrice(int256 spot, int256 strike, int256 vol, int256 tYears) internal pure returns (int256) {
        if (tYears <= 0) return spot > strike ? spot - strike : int256(0);
        (int256 d1, int256 d2) = ds(spot, strike, vol, tYears);
        return (spot * Fixed.ncdf(d1)) / ONE - (strike * Fixed.ncdf(d2)) / ONE;
    }

    function putPrice(int256 spot, int256 strike, int256 vol, int256 tYears) internal pure returns (int256) {
        return callPrice(spot, strike, vol, tYears) - spot + strike; // parity, rate zero
    }

    /// The share of the vault that must sit in stock to manufacture
    /// "the stock, but never below the strike". Always between 0 and 1, which
    /// is why this machine never borrows and never shorts.
    function insuredWeight(int256 spot, int256 strike, int256 vol, int256 tYears) internal pure returns (int256) {
        if (tYears <= 0) return spot > strike ? ONE : int256(0);
        (int256 d1,) = ds(spot, strike, vol, tYears);
        return Fixed.ncdf(d1);
    }
}

