// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StakingRewardSink
 * @notice Receives staking rewards and tracks for frontend display.
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingRewardSink is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    uint256 public totalReceived;
    uint256 public lastRewardAmount;
    uint256 public lastRewardTimestamp;

    event RewardReceived(uint256 amount, uint256 timestamp);

    constructor(address _rewardToken, address _owner) Ownable(_owner) {
        require(_rewardToken != address(0), "zero token");
        rewardToken = IERC20(_rewardToken);
    }

    function notifyRewardAmount(uint256 amount) external {
        require(amount > 0, "amount=0");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        totalReceived += amount;
        lastRewardAmount = amount;
        lastRewardTimestamp = block.timestamp;

        emit RewardReceived(amount, block.timestamp);
    }

    function currentRewardRate() external view returns (uint256) {
        if (block.timestamp == lastRewardTimestamp) return 0;
        return (lastRewardAmount * 1e18) / (block.timestamp - lastRewardTimestamp);
    }
}
