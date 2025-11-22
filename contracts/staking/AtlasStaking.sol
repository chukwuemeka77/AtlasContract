// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AtlasStaking is Ownable {
    IERC20 public immutable atlasToken;
    IERC20 public immutable rewardToken;

    uint256 public totalStaked;
    uint256 public rewardRatePerBlock; // rewards per block
    uint256 public lastUpdateBlock;

    struct Stake {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => Stake) public stakes;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(address _atlasToken, address _rewardToken, uint256 _rewardRatePerBlock) {
        require(_atlasToken != address(0), "Invalid Atlas token");
        require(_rewardToken != address(0), "Invalid reward token");

        atlasToken = IERC20(_atlasToken);
        rewardToken = IERC20(_rewardToken);
        rewardRatePerBlock = _rewardRatePerBlock;
        lastUpdateBlock = block.number;
    }

    // ------------------------------------------------------------
    // INTERNAL: update rewards for a user
    // ------------------------------------------------------------
    function _updateRewards(address user) internal {
        if (totalStaked > 0) {
            uint256 blocksPassed = block.number - lastUpdateBlock;
            uint256 totalReward = blocksPassed * rewardRatePerBlock;
            // reward per staked token
            uint256 rewardPerToken = (totalReward * 1e18) / totalStaked;

            if (user != address(0)) {
                Stake storage s = stakes[user];
                uint256 pending = (s.amount * rewardPerToken) / 1e18 - s.rewardDebt;
                if (pending > 0) {
                    rewardToken.transfer(user, pending);
                    emit RewardClaimed(user, pending);
                }
                s.rewardDebt = (s.amount * rewardPerToken) / 1e18;
            }
            lastUpdateBlock = block.number;
        }
    }

    // ------------------------------------------------------------
    // STAKE tokens
    // ------------------------------------------------------------
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be >0");

        _updateRewards(msg.sender);

        stakes[msg.sender].amount += amount;
        totalStaked += amount;

        atlasToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    // ------------------------------------------------------------
    // UNSTAKE tokens
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
    // VIEW pending rewards
    // ------------------------------------------------------------
    function pendingReward(address user) external view returns (uint256) {
        Stake memory s = stakes[user];
        uint256 blocksPassed = block.number - lastUpdateBlock;
        uint256 totalReward = blocksPassed * rewardRatePerBlock;
        uint256 rewardPerToken = totalStaked > 0 ? (totalReward * 1e18) / totalStaked : 0;
        return (s.amount * rewardPerToken) / 1e18 - s.rewardDebt;
    }

    // ------------------------------------------------------------
    // ADMIN: Update reward rate
    // ------------------------------------------------------------
    function setRewardRate(uint256 newRate) external onlyOwner {
        _updateRewards(address(0));
        rewardRatePerBlock = newRate;
    }

    // ------------------------------------------------------------
    // ADMIN: Recover tokens sent by mistake
    // ------------------------------------------------------------
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}
