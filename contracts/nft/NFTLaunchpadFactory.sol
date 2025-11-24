// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./NFTCollection.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTLaunchpadFactory
 * @notice Factory to deploy NFT collections for launchpad sales
 */
contract NFTLaunchpadFactory is Ownable {
    address[] public allCollections;

    event CollectionCreated(address indexed collection, string name, string symbol, uint256 maxSupply, uint256 mintPrice);

    function createCollection(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 maxSupply,
        uint256 mintPrice,
        address treasury
    ) external onlyOwner returns (address collection) {
        NFTCollection nft = new NFTCollection(name, symbol, baseURI, maxSupply, mintPrice, treasury);
        collection = address(nft);
        allCollections.push(collection);

        emit CollectionCreated(collection, name, symbol, maxSupply, mintPrice);
    }

    function allCollectionsLength() external view returns (uint256) {
        return allCollections.length;
    }
}

