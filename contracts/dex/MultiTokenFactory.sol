// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MultiTokenPair.sol";

contract MultiTokenFactory is Ownable {
    address public vaultAdmin; // Fee recipient
    address[] public allPairs;

    // Mapping to quickly find existing pair
    mapping(address => mapping(address => address)) public getPair;

    // Events
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _vaultAdmin) {
        require(_vaultAdmin != address(0), "Invalid vault admin address");
        vaultAdmin = _vaultAdmin;
    }

    /**
     * @notice Creates a new token pair
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @return pair Address of the newly created pair
     */
    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, "Identical addresses");
        require(tokenA != address(0) && tokenB != address(0), "Zero address");
        require(getPair[tokenA][tokenB] == address(0), "Pair exists");

        // Deploy new pair contract
        MultiTokenPair newPair = new MultiTokenPair(tokenA, tokenB, vaultAdmin);
        pair = address(newPair);

        // Store pair
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }

    /**
     * @notice Returns the total number of pairs
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /**
     * @notice Updates the vault admin address
     */
    function setVaultAdmin(address _vaultAdmin) external onlyOwner {
        require(_vaultAdmin != address(0), "Invalid vault admin");
        vaultAdmin = _vaultAdmin;
    }
}
