// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../token/AtlasToken.sol";

/**
 * @title Launchpad
 * @notice Manages presale participation, token claiming, and vesting hooks
 */
contract Launchpad is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct PresaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    AtlasToken public atlasToken;
    address public treasury; // USDC or ETH collected goes here

    mapping(address => PresaleInfo) public presales;

    event PresaleParticipated(address indexed user, uint256 amount);
    event PresaleClaimed(address indexed user, uint256 amount);

    constructor(AtlasToken _atlasToken, address _treasury, address _admin) Ownable() {
        atlasToken = _atlasToken;
        treasury = _treasury;
        _transferOwnership(_admin); // multisig admin from .env
    }

    /**
     * @notice Users participate in presale
     * @param user The user address
     * @param amount Amount of tokens purchased
     */
    function participate(address user, uint256 amount) external onlyOwner {
        PresaleInfo storage info = presales[user];
        require(block.timestamp < info.endTime || info.endTime == 0, "Presale ended");

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + 30 days; // vesting period
        emit PresaleParticipated(user, amount);
    }

    /**
     * @notice Claim vested tokens after presale
     */
    function claim() external nonReentrant {
        PresaleInfo storage info = presales[msg.sender];
        require(info.totalAllocated > 0, "No allocation");
        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);
        emit PresaleClaimed(msg.sender, claimable);
    }

    /**
     * @notice Compute vested amount for a user
     */
    function _vestedAmount(PresaleInfo memory info) internal view returns (uint256) {
        if (block.timestamp >= info.endTime) {
            return info.totalAllocated - info.totalClaimed;
        }
        // linear vesting
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
