// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../utils/LiquidityLocker.sol";
import "../token/AtlasToken.sol";

contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct SaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool buyerVesting;
        uint256 liquidityAmount;
        uint256 liquidityLockDuration;
        bool liquidityLocked;
    }

    AtlasToken public atlasToken;
    address public treasury; // collected ETH/USDC
    LiquidityLocker public liquidityLocker;

    uint256 public launchpadFee; // in wei (ETH equivalent in Atlas)
    address public feeCollector;

    mapping(address => SaleInfo) public sales;

    event SaleParticipated(address indexed user, uint256 amount);
    event SaleClaimed(address indexed user, uint256 amount);
    event LiquidityLocked(uint256 indexed lockId, uint256 amount, uint256 unlockTime);

    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        LiquidityLocker _liquidityLocker,
        address _feeCollector,
        uint256 _launchpadFee,
        address _admin
    ) Ownable() {
        atlasToken = _atlasToken;
        treasury = _treasury;
        liquidityLocker = _liquidityLocker;
        feeCollector = _feeCollector;
        launchpadFee = _launchpadFee;
        _transferOwnership(_admin);
    }

    /**
     * @notice User participates in sale
     */
    function participate(address user, uint256 amount, bool buyerVesting) external onlyOwner {
        SaleInfo storage info = sales[user];
        require(block.timestamp < info.endTime || info.endTime == 0, "Sale ended");

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + 30 days; // default vesting for buyers
        info.buyerVesting = buyerVesting;

        emit SaleParticipated(user, amount);
    }

    /**
     * @notice Claim tokens after optional buyer vesting
     */
    function claim() external nonReentrant {
        SaleInfo storage info = sales[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);

        emit SaleClaimed(msg.sender, claimable);
    }

    function _vestedAmount(SaleInfo memory info) internal view returns (uint256) {
        if (!info.buyerVesting) {
            return info.totalAllocated - info.totalClaimed;
        }

        if (block.timestamp >= info.endTime) {
            return info.totalAllocated - info.totalClaimed;
        }
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    /**
     * @notice Enforce mandatory liquidity addition and lock
     */
    function addAndLockLiquidity(address lpToken, uint256 amount, uint256 lockDuration) external onlyOwner returns (uint256 lockId) {
        require(amount > 0, "Amount must be > 0");
        require(lockDuration > 0, "Lock duration must be > 0");

        SaleInfo storage info = sales[msg.sender];
        info.liquidityAmount = amount;
        info.liquidityLockDuration = lockDuration;

        // Transfer LP tokens from owner to locker
        IERC20(lpToken).transferFrom(msg.sender, address(liquidityLocker), amount);

        // Lock liquidity
        lockId = liquidityLocker.lockLiquidity(lpToken, amount, lockDuration);
        info.liquidityLocked = true;

        emit LiquidityLocked(lockId, amount, block.timestamp + lockDuration);
    }

    /**
     * @notice Collect launchpad fee in Atlas
     */
    function payLaunchpadFee() external {
        atlasToken.safeTransferFrom(msg.sender, feeCollector, launchpadFee);
    }

    /**
     * @notice Set treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /**
     * @notice Set launchpad fee
     */
    function setLaunchpadFee(uint256 _launchpadFee) external onlyOwner {
        launchpadFee = _launchpadFee;
    }
}
