// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint256;

    // Returns sorted tokens
    function sortTokens(address tokenA, address tokenB)
        internal pure returns (address token0, address token1)
    {
        require(tokenA != tokenB, "LIB: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        require(token0 != address(0), "LIB: ZERO_ADDRESS");
    }

    // Computes CREATE2 deterministic pair address
    function pairFor(address factory, address tokenA, address tokenB)
        internal pure returns (address pair)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);

        pair = address(
            uint160( // cast to address
                uint256( // cast to uint
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            // INIT CODE HASH FROM PAIR CONTRACT
                            hex"a0bb5ddfbafdee5d565d6d7d3c1f2afe7b6f707ae5c538f9bb638b275948f50e"
                            // YOU MUST UPDATE WITH YOUR PAIR BYTECODE HASH
                        )
                    )
                )
            )
        );
    }

    // Fetches reserveA, reserveB
    function getReserves(address factory, address tokenA, address tokenB)
        internal view returns (uint reserveA, uint reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);

        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "LIB: PAIR_NOT_EXISTS");

        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();

        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // Return amountB needed for amountA based on reserves
    function quote(uint amountA, uint reserveA, uint reserveB)
        internal pure returns (uint amountB)
    {
        require(amountA > 0, "LIB: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "LIB: INSUFF_LIQ");

        amountB = amountA.mul(reserveB) / reserveA;
    }

    // Swap input -> output using formula: out = in * 997 / (reserveIn*1000 + in*997)
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        internal pure returns (uint amountOut)
    {
        require(amountIn > 0, "LIB: INSUFF_INPUT");
        require(reserveIn > 0 && reserveOut > 0, "LIB: INSUFF_LIQ");

        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);

        amountOut = numerator / denominator;
    }

    // Reverse quote: amount needed to get output
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        internal pure returns (uint amountIn)
    {
        require(amountOut > 0, "LIB: INSUFF_OUTPUT");
        require(reserveIn > 0 && reserveOut > 0, "LIB: INSUFF_LIQ");

        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);

        amountIn = (numerator / denominator) + 1;
    }

    // Walk entire path for amountOut
    function getAmountsOut(address factory, uint amountIn, address[] memory path)
        internal view returns (uint[] memory amounts)
    {
        require(path.length >= 2, "LIB: INVALID_PATH");

        amounts = new uint[](path.length);

        amounts[0] = amountIn;

        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) =
                getReserves(factory, path[i], path[i + 1]);

            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // Walk entire path in reverse for amountIn needed
    function getAmountsIn(address factory, uint amountOut, address[] memory path)
        internal view returns (uint[] memory amounts)
    {
        require(path.length >= 2, "LIB: INVALID_PATH");

        amounts = new uint[](path.length);

        amounts[amounts.length - 1] = amountOut;

        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) =
                getReserves(factory, path[i - 1], path[i]);

            amounts[i - 1] =
                getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
