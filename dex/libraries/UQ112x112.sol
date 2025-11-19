// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// UQ112x112 = (112-bit integer, 112-bit fraction)
library UQ112x112 {
    uint224 constant Q112 = 2**112;

    function encode(uint112 y) internal pure returns (uint224) {
        return uint224(y) * Q112;
    }

    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224) {
        return x / uint224(y);
    }
}
