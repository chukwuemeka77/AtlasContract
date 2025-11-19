// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LPRewardSink
 * @notice Receives LP rewards from RewardDistributorV2 and tracks emissions for frontend APR calculation.
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LPRewardSink is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    uint256 public totalReceived;        // total rewards received from distributor
    uint256 public lastRewardAmount;     // last reward received
    uint256 public lastRewardTimestamp;

    event RewardReceived(uint256 amount, uint256 timestamp);

    constructor(address _rewardToken, address _owner) Ownable(_owner) {
        require(_rewardToken != address(0), "zero token");
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @notice Called by RewardDistributorV2 after transfer of reward tokens
     */
    function notifyRewardAmount(uint256 amount) external {
        require(amount > 0, "amount=0");
        // pull token from RewardDistributorV2
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        totalReceived += amount;
        lastRewardAmount = amount;
        lastRewardTimestamp = block.timestamp;

        emit RewardReceived(amount, block.timestamp);
    }

    /**
     * @notice Current reward rate (for frontend APR calculation)
     */
    function currentRewardRate() external view returns (uint256) {
        // simple per-second rate based on last reward
        if (block.timestamp == lastRewardTimestamp) return 0;
        return (lastRewardAmount * 1e18) / (block.timestamp - lastRewardTimestamp);
    }
}
