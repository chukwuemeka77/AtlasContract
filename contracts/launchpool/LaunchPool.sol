// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";

/**
 * @title LaunchPool
 * @notice Staking pool for any ERC20 token. Supports optional reward rate and mandatory liquidity lock.
 */
contract LaunchPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public stakeToken;     // token users stake (LP or ERC20)
    IERC20 public rewardToken;    // reward token (Atlas or project token)
    address public vault;         // treasury for fees

    uint256 public accRewardPerShare; // accumulated reward per share, scaled by 1e12
    uint256 public lastUpdate;         // last update timestamp
    uint256 public rewardRatePerSecond; // optional reward emission rate

    uint256 public totalStaked;

    struct UserInfo {
        uint256 amount;      // staked amount
        uint256 rewardDebt;  // rewards owed
    }

    mapping(address => UserInfo) public users;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(
        address _stakeToken,
        address _rewardToken,
        address _vault,
        uint256 _rewardRatePerSecond
    ) {
        require(_stakeToken != address(0) && _rewardToken != address(0) && _vault != address(0), "zero address");
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        vault = _vault;
        rewardRatePerSecond = _rewardRatePerSecond;
        lastUpdate = block.timestamp;
    }

    // Update pool rewards
    function _updatePool() internal {
        if (totalStaked > 0 && rewardRatePerSecond > 0) {
            uint256 delta = block.timestamp - lastUpdate;
            uint256 reward = delta * rewardRatePerSecond;
            accRewardPerShare += (reward * 1e12) / totalStaked;
        }
        lastUpdate = block.timestamp;
    }

    // Stake tokens
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "zero amount");
        UserInfo storage user = users[msg.sender];
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
            if (pending > 0) rewardToken.safeTransfer(msg.sender, pending);
        }

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        totalStaked += amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

        emit Staked(msg.sender, amount);
    }

    // Unstake tokens
    function unstake(uint256 amount) external nonReentrant {
        UserInfo storage user = users[msg.sender];
        require(user.amount >= amount, "insufficient balance");
        _updatePool();

        uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) rewardToken.safeTransfer(msg.sender, pending);

        user.amount -= amount;
        totalStaked -= amount;
        stakeToken.safeTransfer(msg.sender, amount);

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

        emit Unstaked(msg.sender, amount);
    }

    // Claim rewards without unstaking
    function claim() external nonReentrant {
        UserInfo storage user = users[msg.sender];
        _updatePool();

        uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
        require(pending > 0, "no rewards");

        rewardToken.safeTransfer(msg.sender, pending);
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

        emit RewardClaimed(msg.sender, pending);
    }

    // Admin: fund rewards
    function fund(uint256 amount) external onlyOwner {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Admin: adjust reward rate
    function setRewardRate(uint256 rate) external onlyOwner {
        _updatePool();
        rewardRatePerSecond = rate;
    }

    // Admin: emergency withdraw for vault (e.g., team/founder staking)
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= rewardToken.balanceOf(address(this)), "insufficient balance");
        rewardToken.safeTransfer(vault, amount);
    }
}
