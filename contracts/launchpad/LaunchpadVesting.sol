// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../token/AtlasToken.sol";
import "../utils/SafeERC20.sol";

/**
 * @title LaunchpadVesting
 * @notice Handles token vesting schedules for buyers and team/founders
 */
contract LaunchpadVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    AtlasToken public token;
    address public vault; // team/founder vesting vault

    struct VestingInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    mapping(address => VestingInfo) public vestings;

    event TokensClaimed(address indexed user, uint256 amount);

    constructor(AtlasToken _token, address _vault) {
        require(_token != AtlasToken(address(0)) && _vault != address(0), "zero address");
        token = _token;
        vault = _vault;
    }

    /** 
     * @notice Setup vesting schedule for a user
     * @param user Address of the beneficiary
     * @param amount Total tokens allocated
     * @param start Timestamp vesting starts
     * @param end Timestamp vesting ends
     */
    function setVesting(
        address user,
        uint256 amount,
        uint256 start,
        uint256 end
    ) external onlyOwner {
        require(user != address(0), "zero user");
        require(end > start, "invalid duration");
        vestings[user] = VestingInfo({
            totalAllocated: amount,
            totalClaimed: 0,
            startTime: start,
            endTime: end
        });
    }

    /** 
     * @notice Claim vested tokens
     */
    function claim() external nonReentrant {
        VestingInfo storage info = vestings[msg.sender];
        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "nothing to claim");

        info.totalClaimed += claimable;
        token.safeTransfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    /** 
     * @notice Compute claimable vested amount
     */
    function _vestedAmount(VestingInfo memory info) internal view returns (uint256) {
        if (block.timestamp >= info.endTime) return info.totalAllocated - info.totalClaimed;
        if (block.timestamp <= info.startTime) return 0;
        uint256 elapsed = block.timestamp - info.startTime;
        uint256 duration = info.endTime - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    /**
     * @notice Setup mandatory vesting for team/founders
     * @param amount Tokens to allocate
     * @param duration Vesting duration in seconds
     */
    function setupTeamVesting(uint256 amount, uint256 duration) external onlyOwner {
        token.safeTransferFrom(msg.sender, vault, amount);
        vestings[vault] = VestingInfo({
            totalAllocated: amount,
            totalClaimed: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + duration
        });
    }

    /**
     * @notice Admin can update vault address
     */
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "zero vault");
        vault = _vault;
    }
}
