// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MultiTokenPair.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MultiTokenFactory
 * @notice Factory to deploy MultiTokenPair contracts
 */
contract MultiTokenFactory is Ownable {
    address[] public allPairs;
    mapping(address => mapping(address => address)) public getPair; // tokenA => tokenB => pair
    address public feeTo;
    address public admin;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _admin) {
        admin = _admin;
    }

    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, "Identical tokens");
        require(getPair[tokenA][tokenB] == address(0), "Pair exists");

        bytes memory bytecode = type(MultiTokenPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        MultiTokenPair(pair).initialize(tokenA, tokenB);
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);

        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }
}
