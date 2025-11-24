// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LiquidityLocker
 * @notice Lock ERC20 liquidity tokens for a fixed duration
 */
contract LiquidityLocker is Ownable {
    struct Lock {
        uint256 amount;
        uint256 unlockTime;
        address token;
        bool withdrawn;
    }

    Lock[] public locks;
    mapping(address => uint256[]) public userLocks;

    event LiquidityLocked(address indexed user, address indexed token, uint256 amount, uint256 unlockTime);
    event LiquidityWithdrawn(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Lock ERC20 liquidity tokens
     * @param token ERC20 token address (LP token)
     * @param amount Amount to lock
     * @param duration Duration in seconds
     */
    function lockLiquidity(
        address token,
        uint256 amount,
        uint256 duration
    ) external {
        require(amount > 0, "Amount must be > 0");
        require(duration > 0, "Duration must be > 0");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        uint256 unlockTime = block.timestamp + duration;
        locks.push(Lock(amount, unlockTime, token, false));
        uint256 lockId = locks.length - 1;
        userLocks[msg.sender].push(lockId);

        emit LiquidityLocked(msg.sender, token, amount, unlockTime);
    }

    /**
     * @notice Withdraw liquidity after lock expires
     * @param lockId Index of the lock
     */
    function withdrawLiquidity(uint256 lockId) external {
        Lock storage userLock = locks[lockId];
        require(userLock.owner == msg.sender || owner() == msg.sender, "Not authorized");
        require(!userLock.withdrawn, "Already withdrawn");
        require(block.timestamp >= userLock.unlockTime, "Lock not expired");

        userLock.withdrawn = true;
        IERC20(userLock.token).transfer(msg.sender, userLock.amount);

        emit LiquidityWithdrawn(msg.sender, userLock.token, userLock.amount);
    }

    /**
     * @notice Get locks for a user
     */
    function getUserLocks(address user) external view returns (Lock[] memory) {
        uint256[] memory lockIds = userLocks[user];
        Lock[] memory result = new Lock[](lockIds.length);

        for (uint256 i = 0; i < lockIds.length; i++) {
            result[i] = locks[lockIds[i]];
        }

        return result;
    }
}
