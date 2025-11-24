// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../token/AtlasToken.sol";
import "../utils/LiquidityLocker.sol";

interface IPriceOracle {
    function getAtlasEthPrice() external view returns (uint256);
}

contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    // ----------------------------
    // Tokens & Treasury
    // ----------------------------
    AtlasToken public atlasToken;
    address public treasury;           // Collected fees & presale funds
    LiquidityLocker public liquidityLocker;
    IPriceOracle public priceOracle;

    uint256 public launchFeeETH;       // ETH equivalent of launch fee (0.2 ETH)

    // ----------------------------
    // Vesting & Sale Info
    // ----------------------------
    struct SaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool buyerVesting;            // Optional buyer vesting
    }

    struct TeamVestingInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    mapping(address => SaleInfo) public buyers;
    TeamVestingInfo public teamVesting;

    event LaunchpadCreated(address indexed creator, uint256 feePaidAtlas);
    event BuyerParticipated(address indexed buyer, uint256 amount);
    event BuyerClaimed(address indexed buyer, uint256 amount);

    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        LiquidityLocker _liquidityLocker,
        uint256 _launchFeeETH,
        IPriceOracle _priceOracle,
        uint256 _teamAllocation,        // Enforced team vesting allocation
        uint256 _teamVestingDuration    // In seconds
    ) {
        atlasToken = _atlasToken;
        treasury = _treasury;
        liquidityLocker = _liquidityLocker;
        launchFeeETH = _launchFeeETH;
        priceOracle = _priceOracle;

        // Initialize team vesting
        teamVesting.totalAllocated = _teamAllocation;
        teamVesting.startTime = block.timestamp;
        teamVesting.endTime = block.timestamp + _teamVestingDuration;
    }

    // ----------------------------
    // Launchpad creation fee
    // ----------------------------
    function payLaunchFee() internal {
        uint256 atlasPrice = priceOracle.getAtlasEthPrice(); // wei per ATLAS
        uint256 feeInAtlas = (launchFeeETH * 1e18) / atlasPrice;

        require(atlasToken.balanceOf(msg.sender) >= feeInAtlas, "Insufficient ATLAS for fee");
        atlasToken.safeTransferFrom(msg.sender, treasury, feeInAtlas);

        emit LaunchpadCreated(msg.sender, feeInAtlas);
    }

    // ----------------------------
    // Buyer participation
    // ----------------------------
    function participate(uint256 amount, bool vesting) external {
        payLaunchFee();

        SaleInfo storage info = buyers[msg.sender];
        info.totalAllocated += amount;
        info.startTime = block.timestamp;
        info.endTime = vesting ? block.timestamp + 30 days : block.timestamp;
        info.buyerVesting = vesting;

        // Collect payment in USDC or ETH to treasury if needed
        emit BuyerParticipated(msg.sender, amount);
    }

    function claim() external {
        SaleInfo storage info = buyers[msg.sender];
        require(info.totalAllocated > 0, "No allocation");

        uint256 claimable = _vestedAmount(info);
        require(claimable > 0, "Nothing to claim");

        info.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);

        emit BuyerClaimed(msg.sender, claimable);
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

    // ----------------------------
    // Team vesting
    // ----------------------------
    function claimTeamVesting() external onlyOwner {
        uint256 claimable = _teamVestedAmount();
        require(claimable > 0, "Nothing to claim");

        teamVesting.totalClaimed += claimable;
        atlasToken.safeTransfer(msg.sender, claimable);
    }

    function _teamVestedAmount() internal view returns (uint256) {
        if (block.timestamp >= teamVesting.endTime) {
            return teamVesting.totalAllocated - teamVesting.totalClaimed;
        }
        uint256 duration = teamVesting.endTime - teamVesting.startTime;
        uint256 elapsed = block.timestamp - teamVesting.startTime;
        return ((teamVesting.totalAllocated * elapsed) / duration) - teamVesting.totalClaimed;
    }

    // ----------------------------
    // Mandatory liquidity lock
    // ----------------------------
    function lockLiquidity(address lpToken, uint256 amount, uint256 unlockTime) external onlyOwner {
        atlasToken.safeTransferFrom(msg.sender, address(liquidityLocker), amount);
        liquidityLocker.lock(lpToken, amount, unlockTime);
    }

    // ----------------------------
    // Admin updates
    // ----------------------------
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setLaunchFeeETH(uint256 _fee) external onlyOwner {
        launchFeeETH = _fee;
    }
}
