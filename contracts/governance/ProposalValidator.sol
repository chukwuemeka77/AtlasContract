// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title ProposalValidator
/// @notice Validates proposals before they are submitted to the Governor
/// @dev This contract can be extended with custom validation logic
contract ProposalValidator is Ownable {
    uint256 public minVotesRequired;
    uint256 public maxOperations;

    event ProposalValidated(address indexed proposer, bool valid);

    constructor(uint256 _minVotesRequired, uint256 _maxOperations) Ownable(msg.sender) {
        minVotesRequired = _minVotesRequired;
        maxOperations = _maxOperations;
    }

    /// @notice Updates minimum votes required for proposal to pass
    function setMinVotesRequired(uint256 _minVotesRequired) external onlyOwner {
        minVotesRequired = _minVotesRequired;
    }

    /// @notice Updates maximum operations allowed in a proposal
    function setMaxOperations(uint256 _maxOperations) external onlyOwner {
        maxOperations = _maxOperations;
    }

    /// @notice Validates a proposal
    /// @param proposer Address proposing
    /// @param operations Number of operations in the proposal
    /// @param votes Current votes of proposer
    /// @return valid True if proposal meets validation rules
    function validateProposal(
        address proposer,
        uint256 operations,
        uint256 votes
    ) external view returns (bool valid) {
        valid = votes >= minVotesRequired && operations <= maxOperations;
    }
}
