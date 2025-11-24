// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../utils/SafeERC20.sol";
import "../utils/LiquidityLocker.sol";
import "../token/AtlasToken.sol";
import "./LaunchpadVesting.sol"; // Optional module

/**
 * @title LaunchpadSale
 * @notice Handles presale participation, claiming, team/founder vesting, liquidity lock, and launch fee
 */
contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    // -----------------------------
    // Structs
    // -----------------------------
    struct PresaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    struct TeamVestingInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    // -----------------------------
    // State Variables
    // -----------------------------
    AtlasToken public atlasToken;
    address public treasury; // ETH/USDC collected goes here
    address public liquidityLocker;

    uint256 public launchFeeInETH; // from .env, converted to Atlas on deployment
    uint256 public liquidityLockDuration; // e.g., 6 months

    bool public buyerVestingEnabled;

    mapping(address => PresaleInfo) public presales;
    TeamVestingInfo public teamVesting;

    LaunchpadVesting public vestingModule; // optional buyer vesting module

    // -----------------------------
    // Events
    // -----------------------------
    event PresaleParticipated(address indexed user, uint256 amount);
    event PresaleClaimed(address indexed user, uint256 amount);
    event TeamVestingClaimed(address indexed user, uint256 amount);
    event LiquidityLocked(address locker, uint256 amount);

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        address _admin,
        uint256 _launchFeeInETH,
        uint256 _liquidityLockDuration,
        bool _buyerVestingEnabled,
        LaunchpadVesting _vestingModule
    ) Ownable() {
        atlasToken = _atlasToken;
        treasury = _treasury;
        _transferOwnership(_admin);
        launchFeeInETH = _launchFeeInETH;
        liquidityLockDuration = _liquidityLockDuration;
        buyerVestingEnabled = _buyerVestingEnabled;
        vestingModule = _vestingModule;
    }

    // -----------------------------
    // Presale Participation
    // -----------------------------
    function participate(address user, uint256 amount) external onlyOwner {
        PresaleInfo storage info = presales[user];
        require(block.timestamp < info.endTime || info.endTime == 0, "Presale ended");

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + 30 days; // default vesting for buyers if optional
        emit PresaleParticipated(user, amount);
    }

    // -----------------------------
    // Claiming
    // -----------------------------
    function claim() external nonReentrant {
        PresaleInfo storage info = presales[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable;
        if (buyerVestingEnabled && address(vestingModule) != address(0)) {
            claimable = vestingModule.vestedAmount(msg.sender, info.totalAllocated, info.startTime, info.endTime);
        } else {
            claimable = info.totalAllocated - info.totalClaimed;
        }

        require(claimable > 0, "Nothing to claim");
        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);
        emit PresaleClaimed(msg.sender, claimable);
    }

    // -----------------------------
    // Team/Founder Vesting
    // -----------------------------
    function claimTeamVesting() external onlyOwner {
        TeamVestingInfo storage info = teamVesting;
        uint256 claimable = _vestedTeamAmount();
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);
        emit TeamVestingClaimed(msg.sender, claimable);
    }

    function _vestedTeamAmount() internal view returns (uint256) {
        TeamVestingInfo memory info = teamVesting;
        if (block.timestamp >= info.endTime) return info.totalAllocated - info.totalClaimed;
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    // -----------------------------
    // Liquidity Lock
    // -----------------------------
    function lockLiquidity(uint256 amount) external onlyOwner {
        require(liquidityLocker != address(0), "Liquidity locker not set");
        atlasToken.safeTransfer(liquidityLocker, amount);
        LiquidityLocker(liquidityLocker).lockTokens(amount, liquidityLockDuration);
        emit LiquidityLocked(liquidityLocker, amount);
    }

    // -----------------------------
    // Admin functions
    // -----------------------------
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setLiquidityLocker(address locker) external onlyOwner {
        liquidityLocker = locker;
    }

    function setBuyerVestingEnabled(bool enabled) external onlyOwner {
        buyerVestingEnabled = enabled;
    }
}
