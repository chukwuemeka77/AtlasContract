// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";

contract LaunchPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        uint256 rewardRate; // optional
        uint256 totalStaked;
        bool isMeme;        // meme coin flag
    }

    IERC20 public stakeToken;
    IERC20 public rewardToken;
    PoolInfo public pool;

    event Staked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(IERC20 _stakeToken, IERC20 _rewardToken, bool memeFlag) {
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
        pool.isMeme = memeFlag;
    }

    function stake(uint256 amount) external {
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        pool.totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function claimReward(uint256 amount) external {
        if (pool.rewardRate > 0) {
            rewardToken.safeTransfer(msg.sender, amount);
            emit RewardClaimed(msg.sender, amount);
        }
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        pool.rewardRate = rate;
    }
}
