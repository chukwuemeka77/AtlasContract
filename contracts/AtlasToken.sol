// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract AtlasToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event CrossChainMint(address indexed to, uint256 amount, string targetChain, bytes32 indexed requestId);
    event CrossChainBurn(address indexed from, uint256 amount, string targetChain, bytes32 indexed requestId);

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount, bytes32 requestId, string calldata sourceChain) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit CrossChainMint(to, amount, sourceChain, requestId);
    }

    function burnForBridge(uint256 amount, string calldata targetChain, bytes32 requestId) external {
        _burn(msg.sender, amount);
        emit CrossChainBurn(msg.sender, amount, targetChain, requestId);
    }
}
