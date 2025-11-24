// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTCollection is ERC721A, Ownable {
    uint256 public maxSupply;
    string private baseTokenURI;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 _maxSupply,
        address _owner
    ) ERC721A(name, symbol) {
        maxSupply = _maxSupply;
        baseTokenURI = baseURI;
        _transferOwnership(_owner);
    }

    function mint(uint256 quantity) external onlyOwner {
        require(totalSupply() + quantity <= maxSupply, "Exceeds max supply");
        _mint(msg.sender, quantity);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        baseTokenURI = baseURI;
    }
}
