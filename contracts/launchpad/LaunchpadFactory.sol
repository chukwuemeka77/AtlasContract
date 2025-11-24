// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LaunchpadSale.sol";
import "../presale/Vesting.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchpadFactory
 * @notice Factory to deploy LaunchpadSale contracts.
 * - Every sale includes mandatory vesting
 * - Liquidity add is mandatory during finalize
 */
contract LaunchpadFactory is Ownable {
    address public router;        // AtlasRouter address
    address public vault;         // Platform treasury / fee sink
    address[] public allSales;    // All deployed sales

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

    function allSalesLength() external view returns (uint256) {
        return allSales.length;
    }

    /**
     * @notice Create a sale for a token
     * @param token Token being sold
     * @param paymentToken Token used for payment (USDC/WETH)
     * @param price Price per token (scaled by payment token decimals)
     * @param hardcap Max tokens to sell
     * @param tgePercent % released at TGE
     * @param vestingDuration Vesting duration (seconds)
     */
    function createSale(
        address token,
        address paymentToken,
        uint256 price,
        uint256 hardcap,
        uint8 tgePercent,
        uint256 vestingDuration
    ) external returns (address sale, address vesting) {
        require(token != address(0), "LaunchpadFactory: zero token");
        require(paymentToken != address(0), "LaunchpadFactory: zero paymentToken");
        require(vestingDuration > 0, "LaunchpadFactory: vesting required");

        // Deploy vesting contract (mandatory)
        Vesting v = new Vesting(token, msg.sender, vestingDuration);
        vesting = address(v);

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
            vault
        );

        sale = address(s);
        allSales.push(sale);

        emit SaleCreated(msg.sender, sale, vesting, block.timestamp);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "LaunchpadFactory: zero router");
        router = _router;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "LaunchpadFactory: zero vault");
        vault = _vault;
    }
}

