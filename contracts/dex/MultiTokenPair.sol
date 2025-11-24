// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AtlasLPRewards.sol";

/**
 * @title MultiTokenPair
 * @notice ERC20 pair LP with Atlas rewards and mandatory liquidity lock
 */
contract MultiTokenPair is Ownable {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    IERC20 public lpToken;

    AtlasLPRewards public rewards;

    uint256 public totalSupply;
    uint256 public minLockDuration; // from .env

    struct LPInfo {
        uint256 amount;
        uint256 lockEnd;
    }

    mapping(address => LPInfo) public lpBalances;

    event LiquidityAdded(address indexed user, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed user, uint256 amountA, uint256 amountB, uint256 lpBurned);

    constructor(
        address _tokenA,
        address _tokenB,
        address _lpToken,
        address _atlasRewardToken,
        uint256 _minLockDuration  // set from factory using .env value
    ) {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid token addresses");
        require(_lpToken != address(0), "Invalid LP token");

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        lpToken = IERC20(_lpToken);

        rewards = new AtlasLPRewards(_atlasRewardToken);
        minLockDuration = _minLockDuration;
    }

    /// @notice Add liquidity and optionally stake LP for rewards
    function addLiquidity(uint256 amountA, uint256 amountB, bool stakeLP) external {
        require(amountA > 0 && amountB > 0, "Invalid amounts");

        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        uint256 lpMinted = sqrt(amountA * amountB); // proportional LP mint
        totalSupply += lpMinted;

        LPInfo storage userLP = lpBalances[msg.sender];
        userLP.amount += lpMinted;
        userLP.lockEnd = block.timestamp + minLockDuration;

        if (stakeLP) {
            lpToken.transfer(msg.sender, lpMinted); // transfer LP token for staking
            rewards.updateRewardDebt(0, msg.sender);
        }

        emit LiquidityAdded(msg.sender, amountA, amountB, lpMinted);
    }

    /// @notice Remove liquidity after lock
    function removeLiquidity(uint256 lpAmount) external {
        LPInfo storage userLP = lpBalances[msg.sender];
        require(lpAmount > 0 && lpAmount <= userLP.amount, "Invalid amount");
        require(block.timestamp >= userLP.lockEnd, "Liquidity locked");

        uint256 proportion = lpAmount * 1e18 / userLP.amount;
        uint256 amountA = (tokenA.balanceOf(address(this)) * proportion) / 1e18;
        uint256 amountB = (tokenB.balanceOf(address(this)) * proportion) / 1e18;

        userLP.amount -= lpAmount;
        totalSupply -= lpAmount;

        // Instant claim Atlas rewards
        rewards.updateRewardDebt(0, msg.sender);

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    /// @notice Utility: sqrt for LP calculation
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
