// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAtlasLP {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IRewardSink {
    function notifyRewardAmount(uint256 amount) external;
}

contract AtlasLPRewards is Ownable, IRewardSink {
    IERC20 public immutable rewardToken;
    IAtlasLP public immutable lpToken;

    uint256 public accRewardPerShare; // Accumulated rewards per LP token, scaled by 1e12
    mapping(address => uint256) public rewardDebt;

    event RewardsAdded(uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(address _rewardToken, address _lpToken) {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_lpToken != address(0), "Invalid LP token");

        rewardToken = IERC20(_rewardToken);
        lpToken = IAtlasLP(_lpToken);
    }

    // ------------------------------------------------------------
    // IRewardSink: Called by RewardDistributorV2
    // ------------------------------------------------------------
    function notifyRewardAmount(uint256 amount) external override {
        require(amount > 0, "amount=0");
        uint256 lpSupply = lpToken.totalSupply();
        if (lpSupply > 0) {
            accRewardPerShare += (amount * 1e12) / lpSupply;
        }
        emit RewardsAdded(amount);
    }

    // ------------------------------------------------------------
    // CLAIM rewards
    // ------------------------------------------------------------
    function claim() external {
        uint256 pending = pendingReward(msg.sender);
        require(pending > 0, "Nothing to claim");

        rewardDebt[msg.sender] += pending;
        rewardToken.transfer(msg.sender, pending);

        emit RewardClaimed(msg.sender, pending);
    }

    // ------------------------------------------------------------
    // VIEW pending rewards
    // ------------------------------------------------------------
    function pendingReward(address user) public view returns (uint256) {
        uint256 userBalance = lpToken.balanceOf(user);
        uint256 acc = accRewardPerShare;
        uint256 pending = (userBalance * acc) / 1e12 - rewardDebt[user];
        return pending;
    }

    // ------------------------------------------------------------
    // ADMIN: Recover tokens sent by mistake
    // ------------------------------------------------------------
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
