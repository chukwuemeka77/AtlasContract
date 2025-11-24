// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LaunchpadSale.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchpadFactory
 * @notice Deploys new LaunchpadSale contracts for any token
 */
contract LaunchpadFactory is Ownable {
    address[] public sales;
    address public vault;
    address public liquidityLocker;

    event SaleCreated(address indexed creator, address saleContract);

    constructor(address _vault, address _liquidityLocker) {
        require(_vault != address(0) && _liquidityLocker != address(0), "zero address");
        vault = _vault;
        liquidityLocker = _liquidityLocker;
    }

    function createSale(
        address token,
        address treasury,
        uint256 pricePerToken,
        uint256 liquidityPercent,
        bool buyerVesting
    ) external onlyOwner returns (address) {
        LaunchpadSale sale = new LaunchpadSale(
            AtlasToken(token),
            treasury,
            vault,
            liquidityLocker,
            pricePerToken,
            liquidityPercent,
            buyerVesting
        );
        sale.transferOwnership(msg.sender);
        sales.push(address(sale));
        emit SaleCreated(msg.sender, address(sale));
        return address(sale);
    }

    function allSalesLength() external view returns (uint256) {
        return sales.length;
    }
}
