// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AtlasToken.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AtlasBridge
 * @notice Handles cross-chain locking and minting of AtlasToken.
 * Implements relayer-controlled minting/unlocking to prevent double spending.
 */
contract AtlasBridge is Ownable, AccessControl {
    AtlasToken public token;

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    // Mapping to track processed cross-chain messages
    mapping(bytes32 => bool) public processedMessages;

    event Locked(address indexed user, uint256 amount, string targetChain);
    event Unlocked(address indexed user, uint256 amount, string sourceChain);
    event Minted(address indexed user, uint256 amount);

    constructor(AtlasToken _token, address admin) {
        token = _token;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        transferOwnership(admin);
    }

    /**
     * @notice Lock tokens on source chain
     */
    function lock(uint256 amount, string calldata targetChain) external {
        require(amount > 0, "Amount must be > 0");
        token.transferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, targetChain);
    }

    /**
     * @notice Unlock tokens on source chain (after burn on target chain)
     */
    function unlock(address to, uint256 amount, string calldata sourceChain, bytes32 txId) external onlyRole(RELAYER_ROLE) {
        require(!processedMessages[txId], "Already processed");
        require(amount > 0, "Amount must be > 0");

        processedMessages[txId] = true;
        token.transfer(to, amount);
        emit Unlocked(to, amount, sourceChain);
    }

    /**
     * @notice Mint tokens on target chain (bridge)
     */
    function mint(address to, uint256 amount, bytes32 txId) external onlyRole(RELAYER_ROLE) {
        require(!processedMessages[txId], "Already processed");
        require(amount > 0, "Amount must be > 0");

        processedMessages[txId] = true;
        token.mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Set a new relayer
     */
    function setRelayer(address relayer, bool approved) external onlyOwner {
        if (approved) {
            _grantRole(RELAYER_ROLE, relayer);
        } else {
            _revokeRole(RELAYER_ROLE, relayer);
        }
    }
}
