// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../token/AtlasToken.sol";

interface ILiquidityLocker {
    function lockLiquidity(address token, uint256 amount, uint256 unlockTime) external;
}

contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    // -------------------------
    // Core Tokens & Treasury
    // -------------------------
    AtlasToken public atlasToken;
    address public treasury;               // VAULT_ADMIN_ADDRESS
    ILiquidityLocker public liquidityLocker;

    // -------------------------
    // Launch Fee
    // -------------------------
    uint256 public launchFee;              // Fee required to start launch
    mapping(address => bool) public feePaid;

    // -------------------------
    // Sale Info
    // -------------------------
    struct SaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool liquidityLocked;
        bool teamVestingSet;
    }

    mapping(address => SaleInfo) public sales;

    // -------------------------
    // Events
    // -------------------------
    event LaunchFeePaid(address indexed projectOwner, uint256 amount);
    event PresaleParticipated(address indexed user, uint256 amount);
    event PresaleClaimed(address indexed user, uint256 amount);
    event LiquidityLocked(address indexed projectOwner, uint256 amount, uint256 unlockTime);
    event TeamVestingSet(address indexed projectOwner, uint256 totalAmount, uint256 duration);

    // -------------------------
    // Constructor
    // -------------------------
    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        ILiquidityLocker _liquidityLocker,
        uint256 _launchFee,
        address _admin
    ) {
        atlasToken = _atlasToken;
        treasury = _treasury;
        liquidityLocker = _liquidityLocker;
        launchFee = _launchFee;
        _transferOwnership(_admin);
    }

    // -------------------------
    // Launch Fee
    // -------------------------
    function payLaunchFee() external payable {
        require(msg.value >= launchFee, "Insufficient launch fee");
        payable(treasury).transfer(msg.value);
        feePaid[msg.sender] = true;
        emit LaunchFeePaid(msg.sender, msg.value);
    }

    function setLaunchFee(uint256 _launchFee) external onlyOwner {
        launchFee = _launchFee;
    }

    // -------------------------
    // Presale Participation (Buyer)
    // Optional vesting
    // -------------------------
    function participate(address user, uint256 amount, uint256 vestingMonths) external onlyOwner {
        require(feePaid[msg.sender], "Launch fee not paid");
        SaleInfo storage info = sales[user];

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = vestingMonths > 0 ? block.timestamp + vestingMonths * 30 days : block.timestamp;
        emit PresaleParticipated(user, amount);
    }

    // -------------------------
    // Claim Tokens
    // -------------------------
    function claim() external nonReentrant {
        SaleInfo storage info = sales[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);
        emit PresaleClaimed(msg.sender, claimable);
    }

    // -------------------------
    // Team/Founder Vesting (Mandatory)
    // -------------------------
    function setTeamVesting(address team, uint256 totalAmount, uint256 months) external onlyOwner {
        SaleInfo storage info = sales[team];
        require(!info.teamVestingSet, "Team vesting already set");
        require(totalAmount > 0 && months > 0, "Invalid vesting params");

        info.totalAllocated = totalAmount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + months * 30 days;
        info.teamVestingSet = true;

        emit TeamVestingSet(team, totalAmount, months);
    }

    // -------------------------
    // Liquidity Addition & Lock (Mandatory)
    // -------------------------
    function lockLiquidity(address token, uint256 amount, uint256 unlockTime) external onlyOwner {
        require(feePaid[msg.sender], "Launch fee not paid");
        require(amount > 0 && unlockTime > block.timestamp, "Invalid liquidity params");

        IERC20(token).transfer(address(liquidityLocker), amount);
        liquidityLocker.lockLiquidity(token, amount, unlockTime);

        emit LiquidityLocked(msg.sender, amount, unlockTime);
    }

    // -------------------------
    // Internal vesting calculation
    // -------------------------
    function _vestedAmount(SaleInfo memory info) internal view returns (uint256) {
        if (block.timestamp >= info.endTime) {
            return info.totalAllocated - info.totalClaimed;
        }
        if (info.endTime > info.startTime) {
            uint256 duration = info.endTime - info.startTime;
            uint256 elapsed = block.timestamp - info.startTime;
            return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
        }
        return info.totalAllocated - info.totalClaimed;
    }

    // -------------------------
    // Admin
    // -------------------------
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
