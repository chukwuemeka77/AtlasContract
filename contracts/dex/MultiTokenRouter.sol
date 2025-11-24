// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MultiTokenFactory.sol";
import "./MultiTokenPair.sol";
import "../token/AtlasToken.sol";

/**
 * @title MultiTokenRouter
 * @notice Allows swapping between any ERC20 token pairs using MultiTokenFactory pools
 */
contract MultiTokenRouter is Ownable {
    using SafeERC20 for IERC20;

    MultiTokenFactory public factory;
    AtlasToken public atlasToken; // Optional: for fee deduction in ATLAS

    event SwapExecuted(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(MultiTokenFactory _factory, AtlasToken _atlasToken, address _admin) {
        factory = _factory;
        atlasToken = _atlasToken;
        _transferOwnership(_admin);
    }

    /**
     * @notice Swap exact tokens in for token out
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum acceptable output tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param to Recipient address
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to
    ) external {
        require(amountIn > 0, "Amount in zero");
        require(tokenIn != tokenOut, "Identical tokens");

        address pairAddr = factory.getPair(tokenIn, tokenOut);
        require(pairAddr != address(0), "Pair not found");

        IERC20(tokenIn).safeTransferFrom(msg.sender, pairAddr, amountIn);

        uint256 amountOut = MultiTokenPair(pairAddr).swap(tokenIn, amountIn, tokenOut, to);
        require(amountOut >= amountOutMin, "Insufficient output");

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /**
     * @notice Multi-hop swap
     * @param amounts Array of amounts per hop
     * @param path Array of token addresses representing the swap path
     * @param to Recipient address
     */
    function swapTokensForTokensSupportingFeeOnTransfer(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external {
        require(path.length >= 2, "Invalid path");

        IERC20(path[0]).safeTransferFrom(msg.sender, factory.getPair(path[0], path[1]), amountIn);

        uint256 amountOut = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            address pairAddr = factory.getPair(path[i], path[i + 1]);
            require(pairAddr != address(0), "Pair not found");

            amountOut = MultiTokenPair(pairAddr).swap(path[i], amountOut, path[i + 1], i == path.length - 2 ? to : factory.getPair(path[i + 1], path[i + 2]));
        }

        require(amountOut >= amountOutMin, "Insufficient output");
        emit SwapExecuted(msg.sender, path[0], path[path.length - 1], amountIn, amountOut);
    }

    /**
     * @notice Update factory contract if needed
     */
    function setFactory(MultiTokenFactory _factory) external onlyOwner {
        factory = _factory;
    }
}
