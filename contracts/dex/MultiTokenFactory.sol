// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./MultiTokenPair.sol";
import "../token/AtlasToken.sol";

/**
 * @title MultiTokenFactory
 * @notice Deploys and manages MultiTokenPair liquidity pools
 */
contract MultiTokenFactory is Ownable {
    // Mapping of token pairs to pair address
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    // Fee configuration
    uint256 public defaultSwapFee; // in basis points, e.g., 30 = 0.3%
    AtlasToken public atlasToken;   // for any fee logic (if needed)

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 totalPairs);

    constructor(AtlasToken _atlasToken, uint256 _defaultSwapFee, address _admin) {
        atlasToken = _atlasToken;
        defaultSwapFee = _defaultSwapFee;
        _transferOwnership(_admin);
    }

    /**
     * @notice Deploys a new MultiTokenPair for two ERC20 tokens
     */
    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, "Identical tokens");
        require(tokenA != address(0) && tokenB != address(0), "Zero address");
        require(getPair[tokenA][tokenB] == address(0), "Pair exists");

        // deploy new pair
        MultiTokenPair newPair = new MultiTokenPair(
            IERC20(tokenA),
            IERC20(tokenB),
            defaultSwapFee,
            owner()
        );

        pair = address(newPair);
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair; // bi-directional mapping
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }

    /**
     * @notice Update default swap fee for new pairs
     */
    function setDefaultSwapFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee too high"); // max 10%
        defaultSwapFee = _fee;
    }

    /**
     * @notice Returns the number of pairs deployed
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
