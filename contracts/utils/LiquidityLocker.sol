// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LiquidityLocker
 * @notice Locks liquidity tokens (LP) for a fixed period to prevent rug pulls
 */
contract LiquidityLocker is Ownable {
    struct LockInfo {
        address lpToken;
        uint256 amount;
        uint256 unlockTime;
        address owner;
        bool withdrawn;
    }

    LockInfo[] public locks;

    event LiquidityLocked(uint256 indexed lockId, address indexed lpToken, address indexed owner, uint256 amount, uint256 unlockTime);
    event LiquidityWithdrawn(uint256 indexed lockId, address indexed lpToken, address indexed owner, uint256 amount);

    /**
     * @notice Lock LP tokens for a specified duration
     * @param _lpToken Address of the LP token
     * @param _amount Amount of LP tokens to lock
     * @param _lockDuration Duration in seconds for the lock
     */
    function lockLiquidity(address _lpToken, uint256 _amount, uint256 _lockDuration) external returns (uint256 lockId) {
        require(_amount > 0, "Amount must be > 0");
        require(_lockDuration > 0, "Lock duration must be > 0");

        IERC20(_lpToken).transferFrom(msg.sender, address(this), _amount);

        lockId = locks.length;
        locks.push(LockInfo({
            lpToken: _lpToken,
            amount: _amount,
            unlockTime: block.timestamp + _lockDuration,
            owner: msg.sender,
            withdrawn: false
        }));

        emit LiquidityLocked(lockId, _lpToken, msg.sender, _amount, block.timestamp + _lockDuration);
    }

    /**
     * @notice Withdraw LP tokens after lock expires
     * @param _lockId ID of the liquidity lock
     */
    function withdrawLiquidity(uint256 _lockId) external {
        require(_lockId < locks.length, "Invalid lockId");

        LockInfo storage lock = locks[_lockId];
        require(msg.sender == lock.owner, "Not lock owner");
        require(block.timestamp >= lock.unlockTime, "Lock not expired");
        require(!lock.withdrawn, "Already withdrawn");

        lock.withdrawn = true;
        IERC20(lock.lpToken).transfer(lock.owner, lock.amount);

        emit LiquidityWithdrawn(_lockId, lock.lpToken, lock.owner, lock.amount);
    }

    /**
     * @notice Get number of active locks
     */
    function totalLocks() external view returns (uint256) {
        return locks.length;
    }

    /**
     * @notice View details of a lock
     */
    function getLockInfo(uint256 _lockId) external view returns (LockInfo memory) {
        require(_lockId < locks.length, "Invalid lockId");
        return locks[_lockId];
    }
}
