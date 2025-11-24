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
 * @notice Distributes ERC20 rewards to multiple LP token holders proportionally
 */
contract AtlasLPRewards is Ownable, IRewardSink {
    IERC20 public immutable rewardToken;

    struct Pool {
        IAtlasLP lpToken;
        uint256 accRewardPerShare; // Accumulated rewards per LP token, scaled by 1e12
        mapping(address => uint256) rewardDebt;
    }

    Pool[] public pools;

    address public rewardDistributor;

    event PoolAdded(uint256 indexed poolId, address lpToken);
    event RewardsAdded(uint256 indexed poolId, uint256 amount);
    event RewardClaimed(uint256 indexed poolId, address indexed user, uint256 amount);
    event RewardDistributorUpdated(address indexed distributor);

    constructor(address _rewardToken) {
        require(_rewardToken != address(0), "Invalid reward token");
        rewardToken = IERC20(_rewardToken);
    }

    /// @notice Add a new LP pool
    function addPool(IAtlasLP lpToken) external onlyOwner {
        require(address(lpToken) != address(0), "Invalid LP token");
        Pool storage newPool = pools.push();
        newPool.lpToken = lpToken;
        emit PoolAdded(pools.length - 1, address(lpToken));
    }

    /// @notice Set the authorized reward distributor
    function setRewardDistributor(address distributor) external onlyOwner {
        rewardDistributor = distributor;
        emit RewardDistributorUpdated(distributor);
    }

    /// @notice Add rewards to LP holders
    function notifyRewardAmount(uint256 poolId, uint256 amount) external {
        require(amount > 0, "Amount=0");
        require(msg.sender == rewardDistributor || msg.sender == owner(), "Unauthorized");
        Pool storage pool = pools[poolId];

        uint256 lpSupply = pool.lpToken.totalSupply();
        if (lpSupply > 0) {
            pool.accRewardPerShare += (amount * 1e12) / lpSupply;
        }

        rewardToken.transferFrom(msg.sender, address(this), amount);
        emit RewardsAdded(poolId, amount);
    }

    /// @notice Claim pending rewards for a specific pool
    function claim(uint256 poolId) public {
        Pool storage pool = pools[poolId];
        uint256 pending = pendingReward(poolId, msg.sender);
        require(pending > 0, "Nothing to claim");

        pool.rewardDebt[msg.sender] += pending;
        rewardToken.transfer(msg.sender, pending);

        emit RewardClaimed(poolId, msg.sender, pending);
    }

    /// @notice Hook to auto-update rewardDebt on LP changes
    function updateRewardDebt(uint256 poolId, address user) external {
        Pool storage pool = pools[poolId];
        claim(poolId); // instant claim on LP change
    }

    /// @notice View pending rewards
    function pendingReward(uint256 poolId, address user) public view returns (uint256) {
        Pool storage pool = pools[poolId];
        uint256 userBalance = pool.lpToken.balanceOf(user);
        uint256 acc = pool.accRewardPerShare;
        return (userBalance * acc) / 1e12 - pool.rewardDebt[user];
    }

    /// @notice Recover any ERC20 accidentally sent
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    /// @notice Number of LP pools
    function poolLength() external view returns (uint256) {
        return pools.length;
    }
}
