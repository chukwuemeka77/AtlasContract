// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LaunchpadSale.sol";
import "./LaunchpadVesting.sol";
import "../token/AtlasToken.sol";
import "../utils/LiquidityLocker.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchpadFactory
 * @notice Deploys and manages multiple LaunchpadSales
 */
contract LaunchpadFactory is Ownable {
    AtlasToken public atlasToken;
    LiquidityLocker public liquidityLocker;
    LaunchpadVesting public vestingModule;
    address public treasury;

    address[] public allSales;

    event LaunchpadSaleCreated(address indexed sale);

    constructor(
        AtlasToken _atlasToken,
        LiquidityLocker _liquidityLocker,
        LaunchpadVesting _vestingModule,
        address _treasury,
        address _admin
    ) {
        require(address(_atlasToken) != address(0) && _treasury != address(0), "zero address");
        atlasToken = _atlasToken;
        liquidityLocker = _liquidityLocker;
        vestingModule = _vestingModule;
        treasury = _treasury;
        _transferOwnership(_admin);
    }

    /**
     * @notice Deploy a new LaunchpadSale
     * @return sale Address of deployed sale
     */
    function createLaunchpadSale() external onlyOwner returns (address sale) {
        LaunchpadSale newSale = new LaunchpadSale(
            atlasToken,
            treasury,
            vestingModule,
            liquidityLocker,
            owner()
        );
        allSales.push(address(newSale));
        emit LaunchpadSaleCreated(address(newSale));
        return address(newSale);
    }

    function getAllSales() external view returns (address[] memory) {
        return allSales;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero address");
        treasury = _treasury;
    }

    function setVestingModule(LaunchpadVesting _vestingModule) external onlyOwner {
        require(address(_vestingModule) != address(0), "zero address");
        vestingModule = _vestingModule;
    }

    function setLiquidityLocker(LiquidityLocker _locker) external onlyOwner {
        require(address(_locker) != address(0), "zero address");
        liquidityLocker = _locker;
    }
}
