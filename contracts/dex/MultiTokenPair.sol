// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/SafeERC20.sol";

/**
 * @title MultiTokenPair
 * @notice Liquidity pool for two ERC20 tokens
 */
contract MultiTokenPair is ERC20, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token0;
    IERC20 public token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public swapFee; // in basis points, e.g., 30 = 0.3%

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 lpTokens);
    event SwapExecuted(address indexed sender, uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);

    constructor(IERC20 _token0, IERC20 _token1, uint256 _swapFee, address _admin) ERC20("MultiToken LP", "MTLP") {
        require(address(_token0) != address(_token1), "Tokens must differ");
        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;
        _transferOwnership(_admin);
    }

    /**
     * @notice Add liquidity to the pool
     */
    function addLiquidity(uint256 amount0, uint256 amount1) external returns (uint256 lpTokens) {
        require(amount0 > 0 && amount1 > 0, "Amounts must be > 0");

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            lpTokens = sqrt(amount0 * amount1);
        } else {
            lpTokens = min((amount0 * _totalSupply) / reserve0, (amount1 * _totalSupply) / reserve1);
        }

        _mint(msg.sender, lpTokens);

        reserve0 += amount0;
        reserve1 += amount1;

        emit LiquidityAdded(msg.sender, amount0, amount1, lpTokens);
    }

    /**
     * @notice Remove liquidity from the pool
     */
    function removeLiquidity(uint256 lpAmount) external returns (uint256 amount0, uint256 amount1) {
        require(lpAmount > 0, "LP amount must be > 0");
        uint256 _totalSupply = totalSupply();

        amount0 = (lpAmount * reserve0) / _totalSupply;
        amount1 = (lpAmount * reserve1) / _totalSupply;

        _burn(msg.sender, lpAmount);

        reserve0 -= amount0;
        reserve1 -= amount1;

        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, lpAmount);
    }

    /**
     * @notice Swap tokenIn for tokenOut
     */
    function swap(IERC20 tokenIn, uint256 amountIn, IERC20 tokenOut, address recipient) external returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "Invalid tokenIn");
        require(tokenOut == token0 || tokenOut == token1, "Invalid tokenOut");
        require(tokenIn != tokenOut, "tokenIn cannot equal tokenOut");

        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 reserveIn = tokenIn == token0 ? reserve0 : reserve1;
        uint256 reserveOut = tokenOut == token0 ? reserve0 : reserve1;

        uint256 amountInWithFee = (amountIn * (10000 - swapFee)) / 10000;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);

        tokenOut.safeTransfer(recipient, amountOut);

        // update reserves
        if (tokenIn == token0) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }

        emit SwapExecuted(msg.sender, amountIn, amountOut, address(tokenIn), address(tokenOut));
    }

    /**
     * @notice Utility functions
     */
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

    function min(uint x, uint y) internal pure returns (uint) {
        return x < y ? x : y;
    }
}
