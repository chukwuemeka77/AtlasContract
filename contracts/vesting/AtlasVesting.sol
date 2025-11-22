// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/SafeERC20.sol";

contract AtlasVesting {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public admin;
    uint256 public lpDuration;

    struct VestingSchedule {
        uint256 amount;
        uint256 start;
        uint256 duration;
        bool claimed;
    }

    mapping(address => VestingSchedule) public schedules;

    constructor(IERC20 _token, uint256 _lpDuration, address _admin) {
        token = _token;
        lpDuration = _lpDuration;
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    function setSchedule(address user, uint256 amount) external onlyAdmin {
        require(schedules[user].amount == 0, "Schedule exists");
        schedules[user] = VestingSchedule({
            amount: amount,
            start: block.timestamp,
            duration: lpDuration,
            claimed: false
        });
    }

    function claim() external {
        VestingSchedule storage s = schedules[msg.sender];
        require(!s.claimed, "Already claimed");
        require(block.timestamp >= s.start + s.duration, "Vesting not ended");
        s.claimed = true;
        token.safeTransfer(msg.sender, s.amount);
    }
}
