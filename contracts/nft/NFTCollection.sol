// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTCollection
 * @notice Standard ERC721A NFT collection for launchpad sales
 */
contract NFTCollection is ERC721A, Ownable {
    string public baseURI;
    uint256 public maxSupply;
    uint256 public mintPrice;
    address public treasury;

    event NFTMinted(address indexed user, uint256 tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseURI,
        uint256 _maxSupply,
        uint256 _mintPrice,
        address _treasury
    ) ERC721A(_name, _symbol) {
        baseURI = _baseURI;
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        treasury = _treasury;
    }

    function mint(uint256 quantity) external payable {
        require(totalSupply() + quantity <= maxSupply, "Exceeds max supply");
        require(msg.value >= quantity * mintPrice, "Insufficient ETH");

        _mint(msg.sender, quantity);

        // forward ETH to treasury
        payable(treasury).transfer(msg.value);

        for (uint256 i = 0; i < quantity; i++) {
            emit NFTMinted(msg.sender, totalSupply() - quantity + i + 1);
        }
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
