// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/SafeERC20.sol";

contract AtlasVesting {
    using SafeERC20 for IERC20;

    IERC20 public immutable atlasToken;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt; // rewards accrued
        uint256 lastUpdate; // timestamp of last reward calculation
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public rewardRatePerSecond; // rewards per second per token staked

    constructor(IERC20 _atlasToken, uint256 _rewardRatePerSecond) {
        atlasToken = _atlasToken;
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    function stake(uint256 amount) external {
        _updateRewards(msg.sender);
        atlasToken.safeTransferFrom(msg.sender, address(this), amount);
        stakes[msg.sender].amount += amount;
    }

    function unstake(uint256 amount) external {
        require(stakes[msg.sender].amount >= amount, "Not enough staked");
        _updateRewards(msg.sender);
        stakes[msg.sender].amount -= amount;
        atlasToken.safeTransfer(msg.sender, amount);
    }

    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 reward = stakes[msg.sender].rewardDebt;
        stakes[msg.sender].rewardDebt = 0;
        if(reward > 0){
            atlasToken.safeTransfer(msg.sender, reward);
        }
    }

    function _updateRewards(address user) internal {
        StakeInfo storage stakeInfo = stakes[user];
        if(stakeInfo.amount > 0){
            uint256 delta = block.timestamp - stakeInfo.lastUpdate;
            uint256 reward = stakeInfo.amount * delta * rewardRatePerSecond / 1e18;
            stakeInfo.rewardDebt += reward;
        }
        stakeInfo.lastUpdate = block.timestamp;
    }
}
