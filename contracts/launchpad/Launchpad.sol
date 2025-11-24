// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../utils/LiquidityLocker.sol";
import "../token/AtlasToken.sol";

/**
 * @title Launchpad
 * @notice Manages token sale for projects with optional buyer vesting, enforced team vesting,
 *         and mandatory liquidity addition + LP lock.
 */
contract Launchpad is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct SaleInfo {
        uint256 totalAllocated;      // Total tokens allocated to a buyer
        uint256 totalClaimed;        // Already claimed by buyer
        uint256 startTime;           // Sale participation start
        uint256 endTime;             // End of buyer vesting
        bool vestingEnabled;         // Optional vesting for buyer
    }

    AtlasToken public atlasToken;
    address public treasury; // USDC/ETH collected goes here
    address public teamVesting; // Team/founder vesting contract
    LiquidityLocker public liquidityLocker;

    uint256 public tgePercent;   // % released at TGE
    uint256 public lpTokenAmount;  // Tokens allocated for liquidity
    uint256 public lpPaymentAmount; // Payment token amount allocated for liquidity

    mapping(address => SaleInfo) public buyers;

    event Participated(address indexed buyer, uint256 amount);
    event Claimed(address indexed buyer, uint256 amount);
    event FinalizedLiquidity(uint256 lpTokens, uint256 lpPayment);

    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        address _teamVesting,
        LiquidityLocker _liquidityLocker,
        uint8 _tgePercent,
        address _admin
    ) Ownable() {
        require(_tgePercent <= 100, "Invalid TGE %");
        atlasToken = _atlasToken;
        treasury = _treasury;
        teamVesting = _teamVesting;
        liquidityLocker = _liquidityLocker;
        tgePercent = _tgePercent;

        _transferOwnership(_admin); // multisig from .env
    }

    /**
     * @notice Participate in token sale
     * @param buyer Buyer address
     * @param amount Tokens purchased
     * @param vestingEnabled Optional buyer vesting
     */
    function participate(
        address buyer,
        uint256 amount,
        bool vestingEnabled
    ) external onlyOwner {
        SaleInfo storage info = buyers[buyer];
        require(block.timestamp < info.endTime || info.endTime == 0, "Sale ended");

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + 30 days; // linear vesting duration for buyer
        info.vestingEnabled = vestingEnabled;

        emit Participated(buyer, amount);
    }

    /**
     * @notice Claim vested tokens after sale
     */
    function claim() external nonReentrant {
        SaleInfo storage info = buyers[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);

        emit Claimed(msg.sender, claimable);
    }

    /**
     * @notice Compute vested amount for buyer
     */
    function _vestedAmount(SaleInfo memory info) internal view returns (uint256) {
        uint256 tgeAmount = (info.totalAllocated * tgePercent) / 100;

        if (!info.vestingEnabled) {
            // No vesting for buyer → all tokens immediately claimable minus claimed
            return info.totalAllocated - info.totalClaimed;
        }

        if (block.timestamp >= info.endTime) {
            return info.totalAllocated - info.totalClaimed;
        }

        // Linear vesting for remaining tokens
        uint256 remaining = info.totalAllocated - tgeAmount;
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        uint256 vested = (remaining * elapsed) / duration;

        // Add TGE portion if not yet claimed
        if (info.totalClaimed < tgeAmount) {
            vested += tgeAmount;
        }

        return vested - info.totalClaimed;
    }

    /**
     * @notice Finalize sale: transfer collected funds to treasury, add liquidity, lock LP
     * @param paymentToken Payment token (e.g., USDC) for liquidity pair
     */
    function finalize(address paymentToken) external onlyOwner {
        require(lpTokenAmount > 0 && lpPaymentAmount > 0, "Liquidity amounts not set");

        // Transfer funds to treasury
        IERC20(paymentToken).safeTransfer(treasury, lpPaymentAmount);

        // Approve token & payment to liquidity locker
        atlasToken.safeApprove(address(liquidityLocker), lpTokenAmount);
        IERC20(paymentToken).safeApprove(address(liquidityLocker), lpPaymentAmount);

        // Lock LP tokens
        liquidityLocker.lock(lpTokenAmount, block.timestamp + 30 days); // example lock duration
        emit FinalizedLiquidity(lpTokenAmount, lpPaymentAmount);
    }

    /**
     * @notice Set LP allocation before finalizing
     */
    function setLiquidityAmounts(uint256 _lpTokenAmount, uint256 _lpPaymentAmount) external onlyOwner {
        lpTokenAmount = _lpTokenAmount;
        lpPaymentAmount = _lpPaymentAmount;
    }

    /**
     * @notice Enforced team/founder vesting
     */
    function fundTeamVesting(uint256 amount) external onlyOwner {
        atlasToken.safeTransfer(teamVesting, amount);
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
