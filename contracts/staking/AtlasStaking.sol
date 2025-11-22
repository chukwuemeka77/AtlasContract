// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRewardSink {
    function notifyRewardAmount(uint256 amount) external;
}

contract AtlasStaking is Ownable, IRewardSink {
    IERC20 public immutable atlasToken;
    IERC20 public immutable rewardToken;

    uint256 public totalStaked;

    struct Stake {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => Stake) public stakes;

    uint256 public accRewardPerToken; // accumulated reward per staked token, scaled by 1e12

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount);

    constructor(address _atlasToken, address _rewardToken) {
        require(_atlasToken != address(0), "Invalid Atlas token");
        require(_rewardToken != address(0), "Invalid reward token");
        atlasToken = IERC20(_atlasToken);
        rewardToken = IERC20(_rewardToken);
    }

    // ------------------------------------------------------------
    // IRewardSink: called by RewardDistributorV2
    // ------------------------------------------------------------
    function notifyRewardAmount(uint256 amount) external override {
        require(totalStaked > 0, "No stakes");
        accRewardPerToken += (amount * 1e12) / totalStaked;
        emit RewardAdded(amount);
    }

    // ------------------------------------------------------------
    // STAKE ATLAS
    // ------------------------------------------------------------
    function stake(uint256 amount) external {
        require(amount > 0, "Amount=0");
        _updateRewards(msg.sender);

        stakes[msg.sender].amount += amount;
        totalStaked += amount;

        atlasToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    // ------------------------------------------------------------
    // UNSTAKE ATLAS
    // ------------------------------------------------------------
    function unstake(uint256 amount) external {
        Stake storage s = stakes[msg.sender];
        require(amount > 0 && amount <= s.amount, "Invalid amount");

        _updateRewards(msg.sender);

        s.amount -= amount;
        totalStaked -= amount;

        atlasToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    // ------------------------------------------------------------
    // CLAIM rewards without unstaking
    // ------------------------------------------------------------
    function claim() external {
        _updateRewards(msg.sender);
    }

    // ------------------------------------------------------------
    // INTERNAL: update rewards for a user
    // ------------------------------------------------------------
    function _updateRewards(address user) internal {
        Stake storage s = stakes[user];
        uint256 pending = (s.amount * accRewardPerToken) / 1e12 - s.rewardDebt;
        if (pending > 0) {
            rewardToken.transfer(user, pending);
            emit RewardClaimed(user, pending);
        }
        s.rewardDebt = (s.amount * accRewardPerToken) / 1e12;
    }

    // ------------------------------------------------------------
    // VIEW pending rewards
    // ------------------------------------------------------------
    function pendingReward(address user) external view returns (uint256) {
        Stake memory s = stakes[user];
        return (s.amount * accRewardPerToken) / 1e12 - s.rewardDebt;
    }

    // ------------------------------------------------------------
    // ADMIN: Recover tokens sent by mistake
    // ------------------------------------------------------------
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
