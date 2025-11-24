// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LaunchpadSale.sol";
import "../presale/Vesting.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchpadFactory
 * @notice Factory to deploy LaunchpadSale contracts for external projects.
 * - Supports optional vesting and automatic liquidity add to Atlas AMM.
 * - Vault/admin address is taken from VAULT_ADMIN_ADDRESS (no redundant env).
 */
contract LaunchpadFactory is Ownable {
    address public router;     // AtlasRouter address (for liquidity add)
    address public vault;      // Vault admin address (VAULT_ADMIN_ADDRESS)
    address[] public allSales;

    event SaleCreated(
        address indexed creator,
        address sale,
        address vesting,
        uint256 timestamp
    );

    constructor(address _router, address _vault) {
        require(_router != address(0), "LaunchpadFactory: zero router");
        require(_vault != address(0), "LaunchpadFactory: zero vault");
        router = _router;
        vault = _vault;
    }

    /// @notice Number of sales deployed
    function allSalesLength() external view returns (uint256) {
        return allSales.length;
    }

    /**
     * @notice Deploy a new LaunchpadSale
     * @param token Token being sold (project token)
     * @param paymentToken Token used for payment (USDC/WETH/etc.)
     * @param price paymentToken per token (scaled by paymentToken decimals)
     * @param hardcap Max tokens for sale
     * @param tgePercent Percent released at TGE (0-100)
     * @param vestingDuration Vesting period in seconds (0 = no vesting)
     * @param autoAddLiquidity Whether to auto add liquidity on finalize
     */
    function createSale(
        address token,
        address paymentToken,
        uint256 price,
        uint256 hardcap,
        uint8 tgePercent,
        uint256 vestingDuration,
        bool autoAddLiquidity
    ) external returns (address sale, address vesting) {
        require(token != address(0) && paymentToken != address(0), "LaunchpadFactory: zero token");

        // Deploy vesting if needed
        if (vestingDuration > 0) {
            Vesting v = new Vesting(token, msg.sender);
            vesting = address(v);
        } else {
            vesting = address(0);
        }

        // Deploy sale contract
        LaunchpadSale s = new LaunchpadSale(
            msg.sender,
            token,
            paymentToken,
            price,
            hardcap,
            tgePercent,
            vesting,
            router,
            vault,
            autoAddLiquidity
        );
        sale = address(s);
        allSales.push(sale);

        emit SaleCreated(msg.sender, sale, vesting, block.timestamp);
    }

    /// @notice Update router address (onlyOwner)
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "LaunchpadFactory: zero router");
        router = _router;
    }

    /// @notice Update vault address (onlyOwner)
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "LaunchpadFactory: zero vault");
        vault = _vault;
    }
}
