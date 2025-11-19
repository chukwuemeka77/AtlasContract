// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

/**
 * @title Governor
 * @notice Governance module linked with Timelock
 */
contract AtlasGovernor is Governor, GovernorTimelockControl {
    constructor(IGovernorTimelock _timelock)
        Governor("AtlasGovernor")
        GovernorTimelockControl(_timelock)
    {}

    // Voting weight, quorum, proposal logic can be defined here
    function votingDelay() public pure override returns (uint256) {
        return 1; // 1 block
    }

    function votingPeriod() public pure override returns (uint256) {
        return 45818; // ~1 week in blocks
    }

    function quorum(uint256 blockNumber) public pure override returns (uint256) {
        return 1000e18; // example quorum
    }
}
