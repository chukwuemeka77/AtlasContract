// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../token/AtlasToken.sol";
import "../utils/LiquidityLocker.sol";

contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct SaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool buyerVesting; // optional vesting for buyers
        bool isMeme;       // meme coin flag
    }

    AtlasToken public atlasToken;
    address public treasury; // ETH or USDC collected
    LiquidityLocker public liquidityLocker;

    uint256 public launchpadFee; // in Atlas, read from .env
    uint256 public minLiquidity; // minimum liquidity requirement
    uint256 public founderVestingMonths = 3; // mandatory

    mapping(address => SaleInfo) public sales;

    event SaleParticipated(address indexed user, uint256 amount);
    event SaleClaimed(address indexed user, uint256 amount);

    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        LiquidityLocker _locker,
        uint256 _launchpadFee,
        uint256 _minLiquidity,
        address _admin
    ) Ownable() {
        atlasToken = _atlasToken;
        treasury = _treasury;
        liquidityLocker = _locker;
        launchpadFee = _launchpadFee;
        minLiquidity = _minLiquidity;
        _transferOwnership(_admin);
    }

    /** 
     * @notice Participate in sale
     * @param user buyer address
     * @param amount amount purchased
     * @param vesting optional vesting for buyers
     * @param memeFlag true if token is meme coin
     */
    function participate(
        address user,
        uint256 amount,
        bool vesting,
        bool memeFlag
    ) external payable onlyOwner {
        require(msg.value >= launchpadFee, "Launchpad fee not paid");

        SaleInfo storage info = sales[user];
        require(block.timestamp < info.endTime || info.endTime == 0, "Sale ended");

        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = block.timestamp + 30 days;
        info.buyerVesting = vesting;
        info.isMeme = memeFlag;

        emit SaleParticipated(user, amount);
    }

    /**
     * @notice Claim purchased tokens
     */
    function claim() external nonReentrant {
        SaleInfo storage info = sales[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable = info.buyerVesting ? _vestedAmount(info) : info.totalAllocated - info.totalClaimed;
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);

        emit SaleClaimed(msg.sender, claimable);
    }

    /**
     * @notice Compute vested amount for buyers (optional)
     */
    function _vestedAmount(SaleInfo memory info) internal view returns (uint256) {
        if (!info.buyerVesting) return info.totalAllocated - info.totalClaimed;
        if (block.timestamp >= info.endTime) return info.totalAllocated - info.totalClaimed;

        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    /** 
     * @notice Enforce liquidity + founder vesting for meme coins
     */
    function finalizeSale(uint256 liquidityAmount, address tokenAddress) external onlyOwner {
        require(liquidityAmount >= minLiquidity, "Insufficient liquidity");

        // Lock liquidity for meme coins and all tokens
        atlasToken.approve(address(liquidityLocker), liquidityAmount);
        liquidityLocker.lockLiquidity(tokenAddress, liquidityAmount, block.timestamp + 90 days);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
