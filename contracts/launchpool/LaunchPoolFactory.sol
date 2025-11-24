// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LaunchPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LaunchPoolFactory
 * @notice Factory for deploying LaunchPool instances
 */
contract LaunchPoolFactory is Ownable {
    address[] public pools;
    address public admin; // for ownership of deployed pools

    event PoolCreated(address indexed pool, address indexed token, uint256 rewardRate);

    constructor(address _admin) {
        admin = _admin;
    }

    /**
     * @notice Deploy a new LaunchPool
     * @param _rewardToken Address of the reward token
     * @param _stakeToken Address of the token to stake
     * @param _rewardRate Reward rate per second (optional, 0 = no rewards)
     * @param _startTime Pool start time
     * @param _endTime Pool end time
     */
    function createPool(
        address _rewardToken,
        address _stakeToken,
        uint256 _rewardRate,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner returns (address) {
        LaunchPool pool = new LaunchPool(
            _rewardToken,
            _stakeToken,
            _rewardRate,
            _startTime,
            _endTime,
            admin
        );
        pools.push(address(pool));
        emit PoolCreated(address(pool), _stakeToken, _rewardRate);
        return address(pool);
    }

    function getPools() external view returns (address[] memory) {
        return pools;
    }

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }
}
