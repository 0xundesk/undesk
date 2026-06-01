// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Fixed} from "./Fixed.sol";

/// @title BS
library BS {
    int256 internal constant ONE = 1e18;

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
}
