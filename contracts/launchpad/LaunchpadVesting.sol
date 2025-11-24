// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../token/AtlasToken.sol";

/**
 * @title LaunchpadVesting
 * @notice Optional module for linear vesting of buyers or team allocations
 */
contract LaunchpadVesting {
    using SafeERC20 for AtlasToken;

    struct VestingSchedule {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool enabled; // optional vesting toggle
    }

    AtlasToken public atlasToken;

    mapping(address => VestingSchedule) public vestings;

    event TokensClaimed(address indexed user, uint256 amount);

    constructor(AtlasToken _atlasToken) {
        atlasToken = _atlasToken;
    }

    /**
     * @notice Set vesting schedule for a user
     */
    function setVesting(
        address user,
        uint256 amount,
        uint256 duration, // seconds
        bool enabled
    ) external {
        vestings[user] = VestingSchedule({
            totalAllocated: amount,
            totalClaimed: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            enabled: enabled
        });
    }

    /**
     * @notice Claim vested tokens
     */
    function claim() external {
        VestingSchedule storage schedule = vestings[msg.sender];
        require(schedule.totalAllocated > 0, "No allocation");

        uint256 claimable = _vestedAmount(schedule);
        require(claimable > 0, "Nothing to claim");

        schedule.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    /**
     * @notice Internal: calculate vested amount
     */
    function _vestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        if (!schedule.enabled) {
            return schedule.totalAllocated - schedule.totalClaimed;
        }
        if (block.timestamp >= schedule.endTime) {
            return schedule.totalAllocated - schedule.totalClaimed;
        }
        uint256 duration = schedule.endTime - schedule.startTime;
        uint256 elapsed = block.timestamp - schedule.startTime;
        return ((schedule.totalAllocated * elapsed) / duration) - schedule.totalClaimed;
    }

    /**
     * @notice View claimable tokens without changing state
     */
    function claimable(address user) external view returns (uint256) {
        return _vestedAmount(vestings[user]);
    }
}
