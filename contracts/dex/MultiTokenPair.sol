// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MultiTokenPair {
    using SafeERC20 for IERC20;

    address public token0;
    address public token1;
    address public vaultAdmin; // Fee recipient

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public constant FEE_DENOMINATOR = 100; // Percent-based fees

    uint256 public swapFeeRewardPercent;  // e.g., 30
    uint256 public swapFeeTreasuryPercent; // e.g., 70

    mapping(address => uint256) public liquidity; // LP shares
    uint256 public totalLiquidity;

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidityMinted);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidityBurned);
    event Swapped(address indexed user, address inputToken, uint256 inputAmount, address outputToken, uint256 outputAmount);

    constructor(address _token0, address _token1, address _vaultAdmin) {
        require(_token0 != _token1, "Identical tokens");
        require(_vaultAdmin != address(0), "Invalid vault admin");

        token0 = _token0;
        token1 = _token1;
        vaultAdmin = _vaultAdmin;

        // Default fees, can be modified via external setter if needed
        swapFeeRewardPercent = 30;
        swapFeeTreasuryPercent = 70;
    }

    /**
     * @notice Add liquidity to the pool
     */
    function addLiquidity(uint256 amount0, uint256 amount1) external returns (uint256 liquidityMinted) {
        require(amount0 > 0 && amount1 > 0, "Zero amount");

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        if (totalLiquidity == 0) {
            liquidityMinted = sqrt(amount0 * amount1);
        } else {
            liquidityMinted = min((amount0 * totalLiquidity) / reserve0, (amount1 * totalLiquidity) / reserve1);
        }

        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        reserve0 += amount0;
        reserve1 += amount1;

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidityMinted);
    }

    /**
     * @notice Remove liquidity from the pool
     */
    function removeLiquidity(uint256 liquidityAmount) external returns (uint256 amount0, uint256 amount1) {
        require(liquidity[msg.sender] >= liquidityAmount, "Insufficient liquidity");

        amount0 = (liquidityAmount * reserve0) / totalLiquidity;
        amount1 = (liquidityAmount * reserve1) / totalLiquidity;

        liquidity[msg.sender] -= liquidityAmount;
        totalLiquidity -= liquidityAmount;

        reserve0 -= amount0;
        reserve1 -= amount1;

        IERC20(token0).safeTransfer(msg.sender, amount0);
        IERC20(token1).safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidityAmount);
    }

    /**
     * @notice Swap exact input token for output token
     */
    function swap(address inputToken, uint256 inputAmount) external returns (uint256 outputAmount) {
        require(inputToken == token0 || inputToken == token1, "Invalid token");
        require(inputAmount > 0, "Zero amount");

        bool isToken0 = inputToken == token0;
        address outputToken = isToken0 ? token1 : token0;

        uint256 reserveInput = isToken0 ? reserve0 : reserve1;
        uint256 reserveOutput = isToken0 ? reserve1 : reserve0;

        // Calculate fees
        uint256 feeReward = (inputAmount * swapFeeRewardPercent) / FEE_DENOMINATOR;
        uint256 feeTreasury = (inputAmount * swapFeeTreasuryPercent) / FEE_DENOMINATOR;
        uint256 amountAfterFee = inputAmount - feeReward - feeTreasury;

        // Update reserves
        if (isToken0) {
            reserve0 += inputAmount;
        } else {
            reserve1 += inputAmount;
        }

        // Constant product formula: x * y = k
        outputAmount = (amountAfterFee * reserveOutput) / (reserveInput + amountAfterFee);

        // Transfer input
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), inputAmount);

        // Transfer output
        IERC20(outputToken).safeTransfer(msg.sender, outputAmount);

        // Send treasury fees
        IERC20(inputToken).safeTransfer(vaultAdmin, feeTreasury);

        emit Swapped(msg.sender, inputToken, inputAmount, outputToken, outputAmount);

        // Update reserves
        if (isToken0) {
            reserve1 -= outputAmount;
        } else {
            reserve0 -= outputAmount;
        }
    }

    /** @notice Utility functions */
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}
