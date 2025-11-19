// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

contract UniswapV2Router02 {
    using SafeMath for uint256;

    address public immutable factory;
    address public immutable WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    /** ----------------------------------------------------------------
        LIQUIDITY OPERATIONS
    ----------------------------------------------------------------- */

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity)
    {
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }

        (amountA, amountB) =
            _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);

        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal view returns (uint amountA, uint amountB) {
        (uint reserveA, uint reserveB) =
            UniswapV2Library.getReserves(factory, tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }

        uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);

        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "ROUTER: INSUFF_B");
            return (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
            require(amountAOptimal >= amountAMin, "ROUTER: INSUFF_A");
            return (amountAOptimal, amountBDesired);
        }
    }

    /** ----------------------------------------------------------------
        SWAPS
    ----------------------------------------------------------------- */

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts)
    {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);

        require(amounts[amounts.length - 1] >= amountOutMin, "ROUTER: INSUFF_OUTPUT");

        IERC20(path[0]).transferFrom(msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);
    }

    function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);

            address pair = UniswapV2Library.pairFor(factory, input, output);
            (address token0,) = UniswapV2Library.sortTokens(input, output);

            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) =
                input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));

            address to = i < path.length - 2
                ? UniswapV2Library.pairFor(factory, output, path[i + 2])
                : _to;

            IUniswapV2Pair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /** ----------------------------------------------------------------
        SWAP SUPPORT FOR FEE-ON-TRANSFER TOKENS
    ----------------------------------------------------------------- */

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline)
    {
        IERC20(path[0]).transferFrom(msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amountIn
        );

        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);

        _swapSupportingFeeOnTransferTokens(path, to);

        uint amountOut =
            IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore;
        require(amountOut >= amountOutMin, "ROUTER: INSUFF_OUTPUT_FOT");
    }

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);

            address pair = UniswapV2Library.pairFor(factory, input, output);
            (address token0,) = UniswapV2Library.sortTokens(input, output);

            uint amountInput;
            uint amountOutput;

            {   // scope
                uint balance0 = IERC20(token0).balanceOf(pair);
                uint balance1 = IERC20(output).balanceOf(pair);

                (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();

                amountInput = input == token0
                    ? balance0 - reserve0
                    : balance1 - reserve1;
            }

            amountOutput =
                UniswapV2Library.getAmountOut(amountInput,
                IUniswapV2Pair(pair).reserveInput(),
                IUniswapV2Pair(pair).reserveOutput()
            );

            (uint amount0Out, uint amount1Out) =
                input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

            address to =
                i < path.length - 2
                    ? UniswapV2Library.pairFor(factory, output, path[i + 2])
                    : _to;

            IUniswapV2Pair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /** ----------------------------------------------------------------
        WETH SUPPORT
    ----------------------------------------------------------------- */

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, "ROUTER: INVALID_PATH");

        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "ROUTER: INSUFF_OUTPUT");

        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(
            UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0])
        );

        _swap(amounts, path, to);
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, "ROUTER: INVALID_PATH");

        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);

        require(amounts[amounts.length - 1] >= amountOutMin, "ROUTER: INSUFF_OUTPUT");

        IERC20(path[0]).transferFrom(
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, address(this));

        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        payable(to).transfer(amounts[amounts.length - 1]);
    }
}
