// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LaunchpadSale.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchpadFactory
 * @notice Deploy LaunchpadSale contracts for external projects.
 * - Vesting and auto liquidity are optional.
 */
contract LaunchpadFactory is Ownable {
    address public router;  // AtlasRouter address (for optional liquidity add)
    address public vault;   // Platform treasury / fee sink
    address[] public allSales;

    event SaleCreated(
        address indexed creator,
        address sale,
        address vesting,
        uint256 timestamp
    );

    constructor(address _router, address _vault) {
        require(_router != address(0), "zero router");
        require(_vault != address(0), "zero vault");
        router = _router;
        vault = _vault;
    }

    function allSalesLength() external view returns (uint256) {
        return allSales.length;
    }

    /**
     * @notice Create a sale for a token
     * @param token Token being sold (project token)
     * @param paymentToken Token used for payment (e.g., USDC)
     * @param price Payment token per project token (scaled by paymentToken decimals)
     * @param hardcap Total tokens allocated for sale
     * @param tgePercent Percent released at TGE (0-100)
     * @param vesting Duration of vesting in seconds (0 = no vesting)
     * @param autoAddLiquidity Whether to add liquidity on finalize
     */
    function createSale(
        address token,
        address paymentToken,
        uint256 price,
        uint256 hardcap,
        uint8 tgePercent,
        uint256 vesting,
        bool autoAddLiquidity
    ) external returns (address sale, address vestingAddress) {
        require(token != address(0) && paymentToken != address(0), "zero token");

        // Deploy LaunchpadSale contract
        LaunchpadSale s = new LaunchpadSale(
            msg.sender,
            token,
            paymentToken,
            price,
            hardcap,
            tgePercent,
            vesting,
            autoAddLiquidity,
            router,
            vault
        );

        sale = address(s);
        vestingAddress = vesting > 0 ? address(s) : address(0); // Vesting handled internally

        allSales.push(sale);
        emit SaleCreated(msg.sender, sale, vestingAddress, block.timestamp);
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
}
