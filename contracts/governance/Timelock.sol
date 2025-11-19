// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Timelock
 * @notice Executes delayed transactions for governance
 */
contract Timelock is Ownable {
    uint256 public delay;

    event QueueTransaction(address target, uint256 value, string signature, bytes data, uint256 eta);
    event ExecuteTransaction(address target, uint256 value, string signature, bytes data, uint256 eta);

    mapping(bytes32 => bool) public queuedTransactions;

    constructor(uint256 _delay, address _owner) {
        delay = _delay;
        transferOwnership(_owner);
    }

    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyOwner returns (bytes32) {
        require(eta >= block.timestamp + delay, "Eta too soon");
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;
        emit QueueTransaction(target, value, signature, data, eta);
        return txHash;
    }

    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyOwner payable returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Transaction not queued");
        require(block.timestamp >= eta, "Too early");
        queuedTransactions[txHash] = false;

        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Call failed");
        emit ExecuteTransaction(target, value, signature, data, eta);
        return returnData;
    }
}
