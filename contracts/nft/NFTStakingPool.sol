// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NFTStakingPool
 * @notice Allows users to stake ERC20 tokens and earn rewards
 */
contract NFTStakingPool is Ownable, ReentrancyGuard {
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastStakedTime;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public accRewardPerShare;
    uint256 public totalStaked;
    uint256 public rewardRatePerSecond;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(
        IERC20 _stakingToken,
        IERC20 _rewardToken,
        uint256 _rewardRatePerSecond
    ) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    function stake(uint256 amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        _updateRewards(msg.sender);

        stakingToken.transferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        user.lastStakedTime = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount >= amount, "Insufficient staked");

        _updateRewards(msg.sender);

        user.amount -= amount;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimReward() external nonReentrant {
        _updateRewards(msg.sender);
        StakeInfo storage user = stakes[msg.sender];
        uint256 pending = user.rewardDebt;
        require(pending > 0, "No reward");

        user.rewardDebt = 0;
        rewardToken.transfer(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }

    function _updateRewards(address userAddr) internal {
        StakeInfo storage user = stakes[userAddr];
        if (user.amount > 0) {
            uint256 pending = (block.timestamp - user.lastStakedTime) * rewardRatePerSecond * user.amount / 1e18;
            user.rewardDebt += pending;
        }
        user.lastStakedTime = block.timestamp;
    }

    function setRewardRate(uint256 _rewardRatePerSecond) external onlyOwner {
        rewardRatePerSecond = _rewardRatePerSecond;
    }
}
