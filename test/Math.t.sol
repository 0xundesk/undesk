// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Fixed} from "../src/Fixed.sol";

contract MathTest is Test {
    function near(int256 got, int256 want, int256 tol, string memory what) internal pure {
        int256 d = got > want ? got - want : want - got;
        require(d <= tol, what);
    }

    function test_Sqrt() public pure {
        near(int256(Fixed.sqrt(2e18)), 1414213562373095048, 1e6, "sqrt2");
        near(int256(Fixed.sqrt(1e18)), 1e18, 1e6, "sqrt1");
        near(int256(Fixed.sqrt(9e18)), 3e18, 1e6, "sqrt9");
    }

    function test_Ln() public pure {
        near(Fixed.ln(1e18), 0, 1e6, "ln1");
        near(Fixed.ln(2e18), 693147180559945309, 1e8, "ln2");
        near(Fixed.ln(10e18), 2302585092994045684, 1e8, "ln10");
        near(Fixed.ln(5e17), -693147180559945309, 1e8, "ln0.5");
    }

    function test_Exp() public pure {
        near(Fixed.exp(0), 1e18, 1e6, "exp0");
        near(Fixed.exp(1e18), 2718281828459045235, 1e9, "exp1");
        near(Fixed.exp(-1e18), 367879441171442321, 1e9, "exp-1");
        near(Fixed.exp(5e18), 148413159102576603174, 1e12, "exp5");
    }

    function test_Ncdf() public pure {
        near(Fixed.ncdf(0), 5e17, 1e11, "N(0)=0.5");
        near(Fixed.ncdf(1e18), 841344746068543000, 1e11, "N(1)");
        near(Fixed.ncdf(-1e18), 158655253931457000, 1e11, "N(-1)");
        near(Fixed.ncdf(1960000000000000000), 975002104851779000, 1e11, "N(1.96)=0.975");
        near(Fixed.ncdf(-1960000000000000000), 24997895148220000, 1e11, "N(-1.96)");
        near(Fixed.ncdf(3e18), 998650101968369000, 1e11, "N(3)");
    }

}

