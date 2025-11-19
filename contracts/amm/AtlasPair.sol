// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAtlasFactory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

contract AtlasPair is Ownable {
    using UQ112x112 for uint224;

    string public constant name = "Atlas LP Token";
    string public constant symbol = "ALP";
    uint8 public constant decimals = 18;

    IERC20 public token0;
    IERC20 public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; 
    uint32  private blockTimestampLast;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public factory;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external onlyOwner {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /// @notice Returns current reserves
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// @notice Mint liquidity to LP
    function mint(address to) external returns (uint256 liquidity) {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            totalSupply += MINIMUM_LIQUIDITY; // permanently lock
        } else {
            liquidity = Math.min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1);
        }

        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        balanceOf[to] += liquidity;
        totalSupply += liquidity;

        _update(balance0, balance1);

        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Burn LP tokens and withdraw liquidity
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf[msg.sender];
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY");

        uint256 _totalSupply = totalSupply;
        amount0 = liquidity * reserve0 / _totalSupply;
        amount1 = liquidity * reserve1 / _totalSupply;

        balanceOf[msg.sender] -= liquidity;
        totalSupply -= liquidity;

        TransferHelper.safeTransfer(address(token0), to, amount0);
        TransferHelper.safeTransfer(address(token1), to, amount1);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        _update(balance0, balance1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice Swap tokens
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external {
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT_AMOUNT");

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(amount0Out < balance0 && amount1Out < balance1, "INSUFFICIENT_LIQUIDITY");

        if (amount0Out > 0) TransferHelper.safeTransfer(address(token0), to, amount0Out);
        if (amount1Out > 0) TransferHelper.safeTransfer(address(token1), to, amount1Out);

        uint256 balance0Adjusted = token0.balanceOf(address(this));
        uint256 balance1Adjusted = token1.balanceOf(address(this));

        require(balance0Adjusted * balance1Adjusted >= uint256(reserve0) * uint256(reserve1), "K");

        _update(balance0Adjusted, balance1Adjusted);

        emit Swap(msg.sender, 0, 0, amount0Out, amount1Out, to);
    }

    function _update(uint256 balance0_, uint256 balance1_) private {
        require(balance0_ <= type(uint112).max && balance1_ <= type(uint112).max, "OVERFLOW");
        reserve0 = uint112(balance0_);
        reserve1 = uint112(balance1_);
        blockTimestampLast = uint32(block.timestamp % 2**32);
        emit Sync(reserve0, reserve1);
    }
}
