// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchpadVesting
 * @notice Optional module for buyer vesting in LaunchpadSale
 */
contract LaunchpadVesting is Ownable {
    struct VestingSchedule {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    mapping(address => VestingSchedule) public schedules;

    event VestingUpdated(address indexed user, uint256 totalAllocated, uint256 startTime, uint256 endTime);

    /**
     * @notice Set or update vesting schedule for a user
     * @dev Called by LaunchpadSale contract
     */
    function setVesting(
        address user,
        uint256 totalAllocated,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
        require(endTime > startTime, "Invalid vesting period");
        schedules[user] = VestingSchedule(totalAllocated, 0, startTime, endTime);
        emit VestingUpdated(user, totalAllocated, startTime, endTime);
    }

    /**
     * @notice Calculate vested amount for a user at current timestamp
     */
    function vestedAmount(
        address user,
        uint256 totalAllocatedFromSale,
        uint256 saleStartTime,
        uint256 saleEndTime
    ) external view returns (uint256) {
        VestingSchedule memory schedule = schedules[user];

        uint256 totalAllocated = schedule.totalAllocated > 0 ? schedule.totalAllocated : totalAllocatedFromSale;
        uint256 startTime = schedule.startTime > 0 ? schedule.startTime : saleStartTime;
        uint256 endTime = schedule.endTime > 0 ? schedule.endTime : saleEndTime;

        if (block.timestamp >= endTime) {
            return totalAllocated;
        } else if (block.timestamp <= startTime) {
            return 0;
        } else {
            uint256 duration = endTime - startTime;
            uint256 elapsed = block.timestamp - startTime;
            return (totalAllocated * elapsed) / duration;
        }
    }

    /**
     * @notice Get claimable amount for a user, considering already claimed tokens
     */
    function claimableAmount(address user, uint256 totalAllocatedFromSale, uint256 saleStartTime, uint256 saleEndTime, uint256 alreadyClaimed) external view returns (uint256) {
        uint256 vested = vestedAmount(user, totalAllocatedFromSale, saleStartTime, saleEndTime);
        if (vested <= alreadyClaimed) {
            return 0;
        }
        return vested - alreadyClaimed;
    }
}
