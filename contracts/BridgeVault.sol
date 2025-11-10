// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BridgeVault is Ownable {
    event TokenLocked(address indexed user, address indexed token, uint256 amount, string toChain, bytes32 indexed requestId);
    event TokenUnlocked(address indexed user, address indexed token, uint256 amount, string fromChain, bytes32 indexed requestId);

    function lockToken(address token, uint256 amount, string calldata toChain, bytes32 requestId) external {
        require(amount > 0, "Zero amount");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit TokenLocked(msg.sender, token, amount, toChain, requestId);
    }

    // only relayer/owner will call unlock (after verification on source chain)
    function unlockToken(address user, address token, uint256 amount, string calldata fromChain, bytes32 requestId) external onlyOwner {
        IERC20(token).transfer(user, amount);
        emit TokenUnlocked(user, token, amount, fromChain, requestId);
    }

    // owner can rescue accidentally sent tokens (emergency)
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
