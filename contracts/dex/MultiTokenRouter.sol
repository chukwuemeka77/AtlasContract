// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MultiTokenFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MultiTokenRouter
 * @notice Facilitates swaps and liquidity operations for MultiTokenPairs
 */
contract MultiTokenRouter is ReentrancyGuard {
    MultiTokenFactory public factory;

    constructor(address _factory) {
        factory = MultiTokenFactory(_factory);
    }

    function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        MultiTokenPair(pair).addLiquidity(amountA, amountB);
    }

    function removeLiquidity(address tokenA, address tokenB, uint256 liquidity) external {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");
        MultiTokenPair(pair).transferFrom(msg.sender, pair, liquidity);
        MultiTokenPair(pair).removeLiquidity(liquidity);
    }

    function swap(address tokenA, address tokenB, uint256 amountOut, address to) external {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");
        (uint256 reserveA, uint256 reserveB) = (IERC20(tokenA).balanceOf(pair), IERC20(tokenB).balanceOf(pair));
        if (tokenA < tokenB) {
            MultiTokenPair(pair).swap(amountOut, 0, to);
        } else {
            MultiTokenPair(pair).swap(0, amountOut, to);
        }
    }
}
