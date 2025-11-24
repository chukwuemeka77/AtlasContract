// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title NFTCollection
 * @notice A standard ERC721A NFT collection
 */
contract NFTCollection is ERC721A, Ownable {
    using Strings for uint256;

    string public baseURI;
    uint256 public maxSupply;
    uint256 public price;
    bool public saleActive = false;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _price
    ) ERC721A(_name, _symbol) {
        baseURI = _baseURI;
        maxSupply = _maxSupply;
        price = _price;
    }

    modifier saleIsActive() {
        require(saleActive, "Sale not active");
        _;
    }

    /**
     * @notice Mint NFTs
     * @param quantity Number of NFTs to mint
     */
    function mint(uint256 quantity) external payable saleIsActive {
        require(totalSupply() + quantity <= maxSupply, "Exceeds max supply");
        require(msg.value >= price * quantity, "Insufficient ETH");

        _safeMint(msg.sender, quantity);
    }

    /**
     * @notice Set the base URI for token metadata
     */
    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /**
     * @notice Toggle sale status
     */
    function toggleSale() external onlyOwner {
        saleActive = !saleActive;
    }

    /**
     * @notice Withdraw contract balance
     */
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        return string(abi.encodePacked(_baseURI(), tokenId.toString(), ".json"));
    }
}
