// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/SafeERC20.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 released;
        uint256 start;
        uint256 cliff;
        uint256 duration;
    }

    mapping(address => VestingSchedule) public schedules;

    event ScheduleCreated(address indexed beneficiary, uint256 totalAmount);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    constructor(address _token, address _owner) {
        token = IERC20(_token);
        transferOwnership(_owner);
    }

    function setVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration
    ) external onlyOwner {
        require(totalAmount > 0, "Invalid amount");
        schedules[beneficiary] = VestingSchedule(totalAmount, 0, start, cliff, duration);
        emit ScheduleCreated(beneficiary, totalAmount);
    }

    function releasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule storage schedule = schedules[beneficiary];
        if (block.timestamp < schedule.start + schedule.cliff) return 0;
        uint256 elapsed = block.timestamp - schedule.start;
        uint256 vested = (schedule.totalAmount * elapsed) / schedule.duration;
        return vested - schedule.released;
    }

    function release(address beneficiary) external {
        uint256 amount = releasableAmount(beneficiary);
        require(amount > 0, "Nothing to release");
        schedules[beneficiary].released += amount;
        IERC20(address(token)).safeTransfer(beneficiary, amount);
        emit TokensReleased(beneficiary, amount);
    }

    /// @notice Batch release multiple beneficiaries
    function batchRelease(address[] calldata beneficiaries) external {
        for (uint i = 0; i < beneficiaries.length; i++) {
            release(beneficiaries[i]);
        }
    }
}
