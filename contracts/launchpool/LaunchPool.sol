// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";

/**
 * @title LaunchPool
 * @notice Handles staking and rewards distribution
 */
contract LaunchPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public stakedToken;
    IERC20 public rewardToken;
    address public vault;
    uint256 public rewardRate;  // per second, optional (0 = manual reward)
    uint256 public startTime;
    uint256 public endTime;

    struct UserInfo {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 lastClaimed;
    }

    mapping(address => UserInfo) public users;

    uint256 public totalStaked;
    uint256 public accRewardPerToken; // accumulated reward per token (scaled by 1e18)
    uint256 public lastUpdate;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(
        address _owner,
        address _stakedToken,
        address _rewardToken,
        uint256 _rewardRate,
        uint256 _startTime,
        uint256 _endTime,
        address _vault
    ) {
        require(_owner != address(0), "zero owner");
        require(_stakedToken != address(0), "zero stakedToken");
        require(_rewardToken != address(0), "zero rewardToken");
        require(_endTime > _startTime, "invalid time");

        stakedToken = IERC20(_stakedToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        startTime = _startTime;
        endTime = _endTime;
        vault = _vault;

        lastUpdate = startTime;
        _transferOwnership(_owner);
    }

    modifier updatePool() {
        if (block.timestamp > lastUpdate) {
            uint256 duration = block.timestamp > endTime ? endTime - lastUpdate : block.timestamp - lastUpdate;
            if (duration > 0 && totalStaked > 0 && rewardRate > 0) {
                accRewardPerToken += (duration * rewardRate * 1e18) / totalStaked;
            }
            lastUpdate = block.timestamp;
        }
        _;
    }

    function stake(uint256 amount) external nonReentrant updatePool {
        require(amount > 0, "zero stake");
        UserInfo storage user = users[msg.sender];

        // Claim pending rewards
        _claim(msg.sender);

        stakedToken.safeTransferFrom(msg.sender, address(this), amount);
        user.amountStaked += amount;
        user.lastClaimed = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant updatePool {
        UserInfo storage user = users[msg.sender];
        require(amount > 0 && user.amountStaked >= amount, "invalid amount");

        _claim(msg.sender);

        user.amountStaked -= amount;
        totalStaked -= amount;
        stakedToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimReward() external nonReentrant updatePool {
        _claim(msg.sender);
    }

    function _claim(address userAddr) internal {
        UserInfo storage user = users[userAddr];
        uint256 pending = (user.amountStaked * accRewardPerToken) / 1e18 - user.rewardDebt;
        if (pending > 0) {
            rewardToken.safeTransfer(userAddr, pending);
            emit RewardClaimed(userAddr, pending);
        }
        user.rewardDebt = (user.amountStaked * accRewardPerToken) / 1e18;
        user.lastClaimed = block.timestamp;
    }

    // Admin: fund pool with reward tokens
    function fundPool(uint256 amount) external {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "zero vault");
        vault = _vault;
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner updatePool {
        rewardRate = _rewardRate;
    }
}
