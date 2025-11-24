// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MultiTokenPair.sol";

interface IAtlasToken is IERC20 {}

contract MultiTokenFactory is Ownable {
    // ---------------------------------------
    // State
    // ---------------------------------------
    IAtlasToken public immutable atlasToken; // Rewards token
    uint256 public immutable minLockDuration; // From .env / deployment

    // All pairs deployed
    MultiTokenPair[] public allPairs;

    // Pair mapping: tokenA => tokenB => pair
    mapping(address => mapping(address => MultiTokenPair)) public getPair;

    // Events
    event PairCreated(address indexed tokenA, address indexed tokenB, address pair, uint256 totalPairs);

    // ---------------------------------------
    // Constructor
    // ---------------------------------------
    constructor(IAtlasToken _atlasToken, uint256 _minLockDuration) {
        require(address(_atlasToken) != address(0), "Invalid Atlas token");
        atlasToken = _atlasToken;
        minLockDuration = _minLockDuration;
    }

    // ---------------------------------------
    // Deploy a new MultiTokenPair
    // ---------------------------------------
    function createPair(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 rewardRatePerSecond // optional reward rate per second for this pool
    ) external onlyOwner returns (MultiTokenPair pair) {
        require(address(tokenA) != address(tokenB), "Identical tokens");
        require(address(tokenA) != address(0) && address(tokenB) != address(0), "Zero address");
        require(address(getPair[address(tokenA)][address(tokenB)]) == address(0), "Pair exists");

        pair = new MultiTokenPair(
            tokenA,
            tokenB,
            atlasToken,
            minLockDuration,
            rewardRatePerSecond
        );

        allPairs.push(pair);
        getPair[address(tokenA)][address(tokenB)] = pair;
        getPair[address(tokenB)][address(tokenA)] = pair; // bi-directional

        emit PairCreated(address(tokenA), address(tokenB), address(pair), allPairs.length);
    }

    // ---------------------------------------
    // View total pairs
    // ---------------------------------------
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // ---------------------------------------
    // Admin: recover accidentally sent ERC20s
    // ---------------------------------------
    function recoverToken(IERC20 token, uint256 amount) external onlyOwner {
        token.transfer(owner(), amount);
    }
}
