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

/**
 * @title AtlasLPRewards
 * @notice Distributes ERC20 rewards to LP token holders proportionally
 */
contract AtlasLPRewards is Ownable, IRewardSink {
    IERC20 public immutable rewardToken;
    IAtlasLP public immutable lpToken;

    uint256 public accRewardPerShare; // Accumulated rewards per LP token, scaled by 1e12
    mapping(address => uint256) public rewardDebt;

    // Optional: restrict reward notifications to a distributor
    address public rewardDistributor;

    event RewardsAdded(uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardDistributorUpdated(address indexed distributor);

    constructor(address _rewardToken, address _lpToken) {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_lpToken != address(0), "Invalid LP token");

        rewardToken = IERC20(_rewardToken);
        lpToken = IAtlasLP(_lpToken);
    }

    /// @notice Set the authorized reward distributor
    function setRewardDistributor(address distributor) external onlyOwner {
        rewardDistributor = distributor;
        emit RewardDistributorUpdated(distributor);
    }

    /// @notice Add rewards to LP holders (callable only by reward distributor or owner)
    function notifyRewardAmount(uint256 amount) external override {
        require(amount > 0, "Amount=0");
        require(msg.sender == rewardDistributor || msg.sender == owner(), "Unauthorized");

        uint256 lpSupply = lpToken.totalSupply();
        if (lpSupply > 0) {
            accRewardPerShare += (amount * 1e12) / lpSupply;
        }

        rewardToken.transferFrom(msg.sender, address(this), amount);
        emit RewardsAdded(amount);
    }

    /// @notice Claim pending rewards
    function claim() external {
        uint256 pending = pendingReward(msg.sender);
        require(pending > 0, "Nothing to claim");

        rewardDebt[msg.sender] += pending;
        rewardToken.transfer(msg.sender, pending);

        emit RewardClaimed(msg.sender, pending);
    }

    /// @notice View pending rewards for a user
    function pendingReward(address user) public view returns (uint256) {
        uint256 userBalance = lpToken.balanceOf(user);
        uint256 acc = accRewardPerShare;
        uint256 pending = (userBalance * acc) / 1e12 - rewardDebt[user];
        return pending;
    }

    /// @notice Recover any ERC20 accidentally sent
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
