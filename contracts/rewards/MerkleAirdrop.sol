// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MerkleAirdrop
 * @notice Distributes ERC20 tokens using Merkle tree proofs for eligibility verification.
 */
contract MerkleAirdrop is Ownable {
    IERC20 public token;
    bytes32 public merkleRoot;
    mapping(address => bool) public claimed;

    event Claimed(address indexed user, uint256 amount);

    constructor(address _token, bytes32 _merkleRoot) {
        token = IERC20(_token);
        merkleRoot = _merkleRoot;
    }

    function claim(uint256 amount, bytes32[] calldata proof) external {
        require(!claimed[msg.sender], "Already claimed");

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "Invalid proof");

        claimed[msg.sender] = true;
        token.transfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    function updateMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }
}
