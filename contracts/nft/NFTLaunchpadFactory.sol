// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./NFTCollection.sol";

contract NFTLaunchpadFactory is Ownable {
    NFTCollection[] public collections;
    address public treasury; // funds go here

    event NFTCollectionCreated(address indexed collection, address indexed owner, string name, string symbol);

    constructor(address _treasury) {
        treasury = _treasury;
    }

    function createNFTCollection(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 maxSupply
    ) external {
        NFTCollection nft = new NFTCollection(name, symbol, baseURI, maxSupply, msg.sender);
        collections.push(nft);
        emit NFTCollectionCreated(address(nft), msg.sender, name, symbol);
    }

    function getCollections() external view returns (NFTCollection[] memory) {
        return collections;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
