// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../token/AtlasToken.sol";
import "./LaunchpadVesting.sol";
import "../utils/LiquidityLocker.sol";

contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    struct SaleInfo {
        uint256 totalAllocated;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
    }

    AtlasToken public atlasToken;
    address public treasury; // where ETH and USDC go
    LiquidityLocker public liquidityLocker;
    LaunchpadVesting public vestingModule;

    uint256 public launchFee; // in Atlas (ETH equivalent)

    mapping(address => SaleInfo) public presales;
    mapping(address => bool) public isTeamOrFounder;

    event PresaleParticipated(address indexed user, uint256 amount);
    event PresaleClaimed(address indexed user, uint256 amount);
    event TeamVested(address indexed teamMember, uint256 amount);

    constructor(
        AtlasToken _atlasToken,
        address _treasury,
        address _admin,
        LiquidityLocker _locker,
        LaunchpadVesting _vesting,
        uint256 _launchFee
    ) {
        atlasToken = _atlasToken;
        treasury = _treasury;
        liquidityLocker = _locker;
        vestingModule = _vesting;
        launchFee = _launchFee;
        _transferOwnership(_admin);
    }

    /**
     * @notice Buyer participates in presale
     * Optional vesting delegated to LaunchpadVesting
     */
    function participate(address user, uint256 amount, bool useVesting) external onlyOwner {
        require(amount > 0, "Amount 0");

        if (useVesting) {
            vestingModule.setVesting(user, amount, 30 days, true);
        } else {
            SaleInfo storage info = presales[user];
            info.totalAllocated += amount;
            info.startTime = block.timestamp;
            info.endTime = block.timestamp + 30 days; // default period
        }

        // Transfer launch fee in Atlas from user
        atlasToken.safeTransferFrom(user, address(this), launchFee);

        emit PresaleParticipated(user, amount);
    }

    /**
     * @notice Claim buyer tokens (optional vesting)
     */
    function claim() external nonReentrant {
        SaleInfo storage info = presales[msg.sender];

        uint256 claimableAmount = info.totalAllocated > 0 ? _vestedAmount(info) : vestingModule.claimable(msg.sender);
        require(claimableAmount > 0, "Nothing to claim");

        if (info.totalAllocated > 0) {
            info.totalClaimed += claimableAmount;
        } else {
            vestingModule.claim(); // delegate to vesting module
        }

        atlasToken.safeTransfer(msg.sender, claimableAmount);
        emit PresaleClaimed(msg.sender, claimableAmount);
    }

    /**
     * @notice Compute vested amount for buyers without vesting module
     */
    function _vestedAmount(SaleInfo memory info) internal view returns (uint256) {
        if (block.timestamp >= info.endTime) {
            return info.totalAllocated - info.totalClaimed;
        }
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.totalAllocated * elapsed) / duration) - info.totalClaimed;
    }

    /**
     * @notice Mandatory team/founder vesting
     */
    function setTeamVesting(address teamMember, uint256 amount, uint256 duration) external onlyOwner {
        require(amount > 0, "Amount 0");
        isTeamOrFounder[teamMember] = true;
        vestingModule.setVesting(teamMember, amount, duration, true);
        emit TeamVested(teamMember, amount);
    }

    /**
     * @notice Lock mandatory liquidity
     */
    function lockLiquidity(address token, uint256 amount, uint256 duration) external onlyOwner {
        atlasToken.safeApprove(address(liquidityLocker), amount);
        liquidityLocker.lock(token, amount, duration);
    }

    /**
     * @notice Update treasury
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /**
     * @notice Update launch fee (ETH equivalent in Atlas)
     */
    function setLaunchFee(uint256 _fee) external onlyOwner {
        launchFee = _fee;
    }
}
