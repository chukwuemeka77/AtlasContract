// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Multicall
 * @notice Allows batching multiple calls into a single transaction
 */
contract Multicall {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall: call failed");
            results[i] = result;
        }
        return results;
    }
}
