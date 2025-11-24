// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../token/AtlasToken.sol";
import "../utils/SafeERC20.sol";

/**
 * @title LaunchPool
 * @notice Staking pool with optional reward rate
 */
contract LaunchPool is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastUpdated;
    }

    AtlasToken public atlasToken;
    uint256 public rewardRatePerSecond; // optional, can be zero
    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalStaked;

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(
        AtlasToken _atlasToken,
        uint256 _rewardRatePerSecond,
        uint256 _startTime,
        uint256 _endTime,
        address _admin
    ) {
        require(address(_atlasToken) != address(0), "zero token");
        require(_startTime < _endTime, "invalid time");

        atlasToken = _atlasToken;
        rewardRatePerSecond = _rewardRatePerSecond;
        startTime = _startTime;
        endTime = _endTime;

        _transferOwnership(_admin);
    }

    /**
     * @notice Stake Atlas tokens into the pool
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "pool not active");
        require(amount > 0, "zero amount");

        StakeInfo storage user = stakes[msg.sender];

        // Update pending rewards before adding more stake
        if (user.amount > 0) {
            uint256 pending = _pendingReward(msg.sender);
            if (pending > 0) {
                atlasToken.safeTransfer(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        atlasToken.safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        user.lastUpdated = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraw staked tokens + rewards
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount >= amount, "not enough staked");

        uint256 pending = _pendingReward(msg.sender);

        if (pending > 0) {
            atlasToken.safeTransfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        if (amount > 0) {
            user.amount -= amount;
            atlasToken.safeTransfer(msg.sender, amount);
            totalStaked -= amount;
            emit Withdrawn(msg.sender, amount);
        }

        user.lastUpdated = block.timestamp;
    }

    /**
     * @notice Claim only the rewards without withdrawing
     */
    function claimRewards() external nonReentrant {
        uint256 pending = _pendingReward(msg.sender);
        require(pending > 0, "no rewards");

        stakes[msg.sender].lastUpdated = block.timestamp;
        atlasToken.safeTransfer(msg.sender, pending);

        emit RewardClaimed(msg.sender, pending);
    }

    /**
     * @notice Compute pending reward for a user
     */
    function _pendingReward(address userAddr) internal view returns (uint256) {
        StakeInfo memory user = stakes[userAddr];

        if (rewardRatePerSecond == 0 || user.amount == 0) {
            return 0;
        }

        uint256 lastTime = user.lastUpdated;
        if (block.timestamp < startTime) {
            return 0;
        }

        uint256 applicableEnd = block.timestamp > endTime ? endTime : block.timestamp;
        uint256 duration = applicableEnd - lastTime;

        return user.amount * rewardRatePerSecond * duration / 1e18; // scaled by 1e18
    }

    /**
     * @notice Update the reward rate (optional, can be zero)
     */
    function setRewardRate(uint256 _rewardRatePerSecond) external onlyOwner {
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    /**
     * @notice Emergency withdraw without rewards
     */
    function emergencyWithdraw() external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        uint256 staked = user.amount;
        require(staked > 0, "nothing to withdraw");

        user.amount = 0;
        user.rewardDebt = 0;
        user.lastUpdated = block.timestamp;
        totalStaked -= staked;

        atlasToken.safeTransfer(msg.sender, staked);
        emit Withdrawn(msg.sender, staked);
    }
}
