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

    function test_Exp() public pure {
        near(Fixed.exp(0), 1e18, 1e6, "exp0");
        near(Fixed.exp(1e18), 2718281828459045235, 1e9, "exp1");
        near(Fixed.exp(-1e18), 367879441171442321, 1e9, "exp-1");
        near(Fixed.exp(5e18), 148413159102576603174, 1e12, "exp5");
    }

}
