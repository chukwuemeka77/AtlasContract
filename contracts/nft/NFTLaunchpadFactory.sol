// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./NFTCollection.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTLaunchpadFactory
 * @notice Deploy and track multiple NFT collections
 */
contract NFTLaunchpadFactory is Ownable {
    NFTCollection[] public collections;

    event CollectionCreated(address indexed creator, address collection);

    /**
     * @notice Deploy a new NFT collection
     */
    function createCollection(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _price
    ) external onlyOwner returns (address) {
        NFTCollection collection = new NFTCollection(_name, _symbol, _baseURI, _maxSupply, _price);
        collections.push(collection);

        emit CollectionCreated(msg.sender, address(collection));
        return address(collection);
    }

    /**
     * @notice Get total collections
     */
    function getCollections() external view returns (NFTCollection[] memory) {
        return collections;
    }
}
