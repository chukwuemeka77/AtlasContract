// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../token/AtlasToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract AtlasBridge is Ownable, AccessControl {
    AtlasToken public token;
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    event Locked(address indexed user, uint256 amount, string targetChain);
    event Minted(address indexed user, uint256 amount);
    event Unlocked(address indexed user, uint256 amount);

    mapping(bytes32 => bool) public processedMessages;

    constructor(AtlasToken _token, address admin) {
        token = _token;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function lock(uint256 amount, string calldata targetChain) external {
        token.transferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, targetChain);
    }

    function mint(address to, uint256 amount, bytes32 txId) external onlyRole(RELAYER_ROLE) {
        require(!processedMessages[txId], "Already processed");
        processedMessages[txId] = true;
        token.bridgeMint(to, amount);
        emit Minted(to, amount);
    }

    function unlock(address to, uint256 amount, bytes32 txId) external onlyRole(RELAYER_ROLE) {
        require(!processedMessages[txId], "Already processed");
        processedMessages[txId] = true;
        token.transfer(to, amount);
        emit Unlocked(to, amount);
    }
}
