// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../token/AtlasToken.sol";
import "../utils/SafeERC20.sol";
import "./LaunchpadVesting.sol";
import "../utils/LiquidityLocker.sol";

/**
 * @title LaunchpadSale
 * @notice Handles presale participation, token claiming, optional buyer vesting, and mandatory liquidity
 */
contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    AtlasToken public atlasToken;
    address public treasury; // USDC or ETH collected
    LaunchpadVesting public vestingModule;
    LiquidityLocker public liquidityLocker;

    struct SaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool vestingEnabled; // optional vesting for buyers
    }

    mapping(address => SaleInfo) public sales;

    event SaleParticipated(address indexed user, uint256 amount, bool vesting);
    event SaleClaimed(address indexed user, uint256 amount);
    event LiquidityAdded(address indexed locker, uint256 amount);

    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        LaunchpadVesting _vestingModule,
        LiquidityLocker _liquidityLocker,
        address _admin
    ) {
        require(address(_atlasToken) != address(0) && _treasury != address(0), "zero address");
        atlasToken = _atlasToken;
        treasury = _treasury;
        vestingModule = _vestingModule;
        liquidityLocker = _liquidityLocker;
        _transferOwnership(_admin); // admin from .env
    }

    /**
     * @notice Participate in presale
     * @param user Buyer address
     * @param amount Token allocation
     * @param enableVesting True to enable vesting for this buyer
     */
    function participate(
        address user,
        uint256 amount,
        bool enableVesting
    ) external onlyOwner {
        SaleInfo storage info = sales[user];
        require(block.timestamp < info.endTime || info.endTime == 0, "Sale ended");

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + 30 days;
        info.vestingEnabled = enableVesting;

        if (enableVesting) {
            vestingModule.setVesting(user, amount, block.timestamp, block.timestamp + 30 days);
        }

        emit SaleParticipated(user, amount, enableVesting);
    }

    /**
     * @notice Claim tokens after sale
     */
    function claim() external nonReentrant {
        SaleInfo storage info = sales[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable;
        if (info.vestingEnabled) {
            vestingModule.claim();
            claimable = vestingModule._vestedAmount(
                vestingModule.vestings(msg.sender)
            );
        } else {
            claimable = info.totalAllocated - info.totalClaimed;
            require(claimable > 0, "Nothing to claim");
            info.totalClaimed += claimable;
            atlasToken.safeTransfer(msg.sender, claimable);
        }

        emit SaleClaimed(msg.sender, claimable);
    }

    /**
     * @notice Add and lock liquidity (mandatory)
     * @param amount Amount of tokens to add to liquidity
     * @param unlockTime Timestamp for liquidity unlock
     */
    function addLiquidity(uint256 amount, uint256 unlockTime) external onlyOwner {
        require(amount > 0, "Zero liquidity");
        atlasToken.safeTransfer(address(liquidityLocker), amount);
        liquidityLocker.lockTokens(address(atlasToken), amount, unlockTime);

        emit LiquidityAdded(address(liquidityLocker), amount);
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero address");
        treasury = _treasury;
    }

    /**
     * @notice Update vesting module
     */
    function setVestingModule(LaunchpadVesting _vestingModule) external onlyOwner {
        require(address(_vestingModule) != address(0), "zero address");
        vestingModule = _vestingModule;
    }
}
