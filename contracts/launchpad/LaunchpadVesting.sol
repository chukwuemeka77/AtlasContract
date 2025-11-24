// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../token/AtlasToken.sol";

/**
 * @title LaunchpadVesting
 * @notice Optional buyer vesting module for Launchpad presales
 */
contract LaunchpadVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct VestingInfo {
        uint256 totalAllocated;   // Total tokens allocated to user
        uint256 totalClaimed;     // Tokens already claimed
        uint256 startTime;        // Vesting start timestamp
        uint256 endTime;          // Vesting end timestamp
    }

    AtlasToken public atlasToken;

    mapping(address => VestingInfo) public vestings;

    event BuyerVestingSet(address indexed buyer, uint256 amount, uint256 startTime, uint256 endTime);
    event BuyerVestingClaimed(address indexed buyer, uint256 amount);

    constructor(AtlasToken _atlasToken, address _admin) Ownable() {
        atlasToken = _atlasToken;
        _transferOwnership(_admin);
    }

    /**
     * @notice Set vesting schedule for a buyer (optional)
     * @param buyer Address of the buyer
     * @param amount Total token allocation
     * @param duration Duration of vesting in seconds
     */
    function setVesting(address buyer, uint256 amount, uint256 duration) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(duration > 0, "Duration must be > 0");

        VestingInfo storage info = vestings[buyer];
        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + duration;

        emit BuyerVestingSet(buyer, amount, info.startTime, info.endTime);
    }

    /**
     * @notice Claim vested tokens
     */
    function claim() external nonReentrant {
        VestingInfo storage info = vestings[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);

        emit BuyerVestingClaimed(msg.sender, claimable);
    }

    /**
     * @notice Compute vested amount for a user (linear vesting)
     */
    function _vestedAmount(VestingInfo memory info) internal view returns (uint256) {
        if (block.timestamp >= info.endTime) {
            return info.totalAllocated - info.totalClaimed;
        }
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    /**
     * @notice View claimable amount for a buyer
     */
    function claimable(address buyer) external view returns (uint256) {
        return _vestedAmount(vestings[buyer]);
    }

    /**
     * @notice Emergency function to recover tokens (if needed)
     */
    function recoverTokens(address to, uint256 amount) external onlyOwner {
        atlasToken.safeTransfer(to, amount);
    }
}
