// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MultiTokenPair.sol";

interface IAtlasToken is IERC20 {}

contract MultiTokenRouter is Ownable {
    // ---------------------------------------
    // State
    // ---------------------------------------
    IAtlasToken public immutable atlasToken;
    MultiTokenPair public factory; // reference to factory for pair creation / lookup

    event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event LiquidityRemoved(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 lpTokens);

    // ---------------------------------------
    // Constructor
    // ---------------------------------------
    constructor(IAtlasToken _atlasToken, MultiTokenPair _factory) {
        require(address(_atlasToken) != address(0), "Invalid Atlas token");
        require(address(_factory) != address(0), "Invalid factory");
        atlasToken = _atlasToken;
        factory = _factory;
    }

    // ---------------------------------------
    // Swap exact input tokens for another
    // ---------------------------------------
    function swapExactTokensForTokens(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        require(amountIn > 0, "Zero input");
        MultiTokenPair pair = factory.getPair(address(tokenIn), address(tokenOut));
        require(address(pair) != address(0), "Pair not found");

        tokenIn.transferFrom(msg.sender, address(pair), amountIn);
        uint256 amountOut = pair.swap(msg.sender, tokenIn, tokenOut, amountIn);
        require(amountOut >= minAmountOut, "Slippage exceeded");

        emit Swapped(msg.sender, address(tokenIn), address(tokenOut), amountIn, amountOut);
    }

    // ---------------------------------------
    // Add liquidity to a pair
    // ---------------------------------------
    function addLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external returns (uint256 lpTokens) {
        MultiTokenPair pair = factory.getPair(address(tokenA), address(tokenB));
        require(address(pair) != address(0), "Pair not found");

        tokenA.transferFrom(msg.sender, address(pair), amountADesired);
        tokenB.transferFrom(msg.sender, address(pair), amountBDesired);

        lpTokens = pair.addLiquidity(msg.sender, amountADesired, amountBDesired);

        emit LiquidityAdded(msg.sender, address(tokenA), address(tokenB), amountADesired, amountBDesired, lpTokens);
    }

    // ---------------------------------------
    // Remove liquidity from a pair
    // ---------------------------------------
    function removeLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 lpAmount
    ) external returns (uint256 amountA, uint256 amountB) {
        MultiTokenPair pair = factory.getPair(address(tokenA), address(tokenB));
        require(address(pair) != address(0), "Pair not found");

        (amountA, amountB) = pair.removeLiquidity(msg.sender, lpAmount);

        emit LiquidityRemoved(msg.sender, address(tokenA), address(tokenB), amountA, amountB, lpAmount);
    }

    // ---------------------------------------
    // Admin: recover accidentally sent ERC20
    // ---------------------------------------
    function recoverToken(IERC20 token, uint256 amount) external onlyOwner {
        token.transfer(owner(), amount);
    }
}
