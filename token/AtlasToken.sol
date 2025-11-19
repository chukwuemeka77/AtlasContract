// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AtlasToken - Main governance + utility token for the Atlas ecosystem
/// @notice Includes mint, burn, governance voting & bridge roles.
contract AtlasToken is ERC20Votes, AccessControl, Ownable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ======== CONSTRUCTOR =========
    constructor(
        string memory name_,
        string memory symbol_,
        address multisig
    ) 
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        Ownable(multisig)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, multisig);
        _grantRole(MINTER_ROLE, multisig);
        _grantRole(BURNER_ROLE, multisig);
        _grantRole(BRIDGE_ROLE, multisig);
    }

    // ======== MINTING =========
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ======== BURN =========
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address user, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(user, amount);
    }

    // ======== BRIDGE HOOKS =========
    function bridgeMint(address to, uint256 amount) external onlyRole(BRIDGE_ROLE) {
        _mint(to, amount);
    }

    function bridgeBurn(address from, uint256 amount) external onlyRole(BRIDGE_ROLE) {
        _burn(from, amount);
    }

    // ======== INTERNAL OVERRIDES FOR ERC20Votes =========
    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address from, uint256 amount)
        internal override(ERC20, ERC20Votes)
    {
        super._burn(from, amount);
    }
}
