// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityLocker is Ownable {
    struct LockInfo {
        uint256 amount;
        uint256 unlockTime;
        bool claimed;
    }

    // token => user => lock info
    mapping(address => mapping(address => LockInfo)) public locks;

    uint256 public immutable minLockDuration; // seconds

    event LiquidityLocked(address indexed token, address indexed user, uint256 amount, uint256 unlockTime);
    event LiquidityUnlocked(address indexed token, address indexed user, uint256 amount);

    constructor(uint256 _minLockDuration) {
        require(_minLockDuration > 0, "Invalid duration");
        minLockDuration = _minLockDuration;
    }

    /**
     * @notice Lock liquidity tokens for the minimum duration
     */
    function lock(address token, address user, uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        LockInfo storage info = locks[token][user];
        info.amount += amount;
        info.unlockTime = block.timestamp + minLockDuration;
        info.claimed = false;

        emit LiquidityLocked(token, user, amount, info.unlockTime);
    }

    /**
     * @notice Unlock tokens after lock duration
     */
    function unlock(address token, address user) external {
        LockInfo storage info = locks[token][user];
        require(info.amount > 0, "No liquidity locked");
        require(block.timestamp >= info.unlockTime, "Still locked");
        require(!info.claimed, "Already claimed");

        uint256 amount = info.amount;
        info.claimed = true;
        IERC20(token).transfer(user, amount);

        emit LiquidityUnlocked(token, user, amount);
    }

    /**
     * @notice View locked info for a user
     */
    function getLockInfo(address token, address user) external view returns (LockInfo memory) {
        return locks[token][user];
    }
}
