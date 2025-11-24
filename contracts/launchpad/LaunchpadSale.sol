// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../utils/SafeERC20.sol";
import "../token/AtlasToken.sol";
import "../utils/LiquidityLocker.sol";

/**
 * @title LaunchpadSale
 * @notice Manages token presale, optional buyer vesting, and mandatory liquidity lock
 */
contract LaunchpadSale is Ownable, ReentrancyGuard {
    using SafeERC20 for AtlasToken;

    AtlasToken public saleToken;       // token being sold
    address public treasury;           // USDC or ETH collected
    address public vault;              // team/founder vesting and liquidity lock
    LiquidityLocker public liquidityLocker;

    uint256 public pricePerToken;      // presale price in USDC
    uint256 public liquidityPercent;   // % of raised funds to lock as liquidity
    bool public buyerVesting;          // optional buyer vesting flag

    struct BuyerInfo {
        uint256 amountBought;
        uint256 claimed;
        uint256 startTime;
        uint256 endTime;
    }

    mapping(address => BuyerInfo) public buyers;

    event Purchased(address indexed buyer, uint256 amount);
    event Claimed(address indexed buyer, uint256 amount);

    constructor(
        AtlasToken _saleToken,
        address _treasury,
        address _vault,
        address _liquidityLocker,
        uint256 _pricePerToken,
        uint256 _liquidityPercent,
        bool _buyerVesting
    ) {
        require(_treasury != address(0) && _vault != address(0) && _liquidityLocker != address(0), "zero address");
        saleToken = _saleToken;
        treasury = _treasury;
        vault = _vault;
        liquidityLocker = LiquidityLocker(_liquidityLocker);
        pricePerToken = _pricePerToken;
        liquidityPercent = _liquidityPercent;
        buyerVesting = _buyerVesting;
    }

    function buy(uint256 amount) external nonReentrant {
        require(amount > 0, "zero amount");

        uint256 cost = amount * pricePerToken;
        IERC20(usdc()).safeTransferFrom(msg.sender, treasury, cost);

        BuyerInfo storage buyer = buyers[msg.sender];
        buyer.amountBought += amount;

        if (buyerVesting) {
            buyer.startTime = block.timestamp;
            buyer.endTime = block.timestamp + 30 days; // optional linear vesting
        } else {
            buyer.claimed += amount;
            saleToken.safeTransfer(msg.sender, amount);
        }

        emit Purchased(msg.sender, amount);
    }

    function claim() external nonReentrant {
        require(buyerVesting, "vesting not enabled");
        BuyerInfo storage buyer = buyers[msg.sender];
        uint256 claimable = _vestedAmount(buyer);
        require(claimable > 0, "nothing to claim");

        buyer.claimed += claimable;
        saleToken.safeTransfer(msg.sender, claimable);
        emit Claimed(msg.sender, claimable);
    }

    function _vestedAmount(BuyerInfo memory info) internal view returns (uint256) {
        if (block.timestamp >= info.endTime) return info.amountBought - info.claimed;
        uint256 duration = info.endTime - info.startTime;
        uint256 elapsed = block.timestamp - info.startTime;
        return ((info.amountBought * elapsed) / duration) - info.claimed;
    }

    function lockLiquidity(uint256 tokenAmount, address lpToken) external onlyOwner {
        require(tokenAmount > 0, "zero amount");
        saleToken.safeTransfer(address(liquidityLocker), tokenAmount);
        liquidityLocker.lockLP(lpToken, tokenAmount, vault); // mandatory
    }

    function usdc() public pure returns (address) {
        return 0xYourUSDCAddress; // from .env
    }

    // Admin: update price
    function setPrice(uint256 _price) external onlyOwner {
        pricePerToken = _price;
    }
}
