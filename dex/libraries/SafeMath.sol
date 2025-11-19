// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library SafeMath {
    function add(uint a, uint b) internal pure returns (uint) {
        return a + b;
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        return a - b;
    }

    function mul(uint a, uint b) internal pure returns (uint) {
        return a * b;
    }

    function div(uint a, uint b) internal pure returns (uint) {
        return a / b;
    }
}
