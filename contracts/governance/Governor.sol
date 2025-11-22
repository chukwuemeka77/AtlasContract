// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "./AtlasStaking.sol";
import "./Timelock.sol";

/**
 * @title AtlasGovernor
 * @notice Governance module for Atlas
 * @dev Voting power is determined by staked ATLAS tokens; admin/governor has highest fixed power
 */
contract AtlasGovernor is Governor, GovernorTimelockControl {
    AtlasStaking public stakingContract;
    address public governor; // admin address with highest voting power

    constructor(
        address _stakingContract,
        IGovernorTimelock _timelock,
        address _governor
    )
        Governor("AtlasGovernor")
        GovernorTimelockControl(_timelock)
    {
        require(_stakingContract != address(0), "Invalid staking contract");
        require(_governor != address(0), "Invalid governor");
        stakingContract = AtlasStaking(_stakingContract);
        governor = _governor;
    }

    // ------------------------------------------------------------
    // GOVERNOR OVERRIDES
    // ------------------------------------------------------------
    function votingDelay() public pure override returns (uint256) {
        return 1; // 1 block delay
    }

    function votingPeriod() public pure override returns (uint256) {
        return 45818; // ~1 week in blocks
    }

    function quorum(uint256 /*blockNumber*/) public pure override returns (uint256) {
        return 1000e18; // example quorum
    }

    // ------------------------------------------------------------
    // GET VOTES (Weighted by Staking; governor/admin override)
    // ------------------------------------------------------------
    function getVotes(address account, uint256 /*blockNumber*/) public view override returns (uint256) {
        if (account == governor) {
            // governor/admin has max power
            return 1_000_000_000_000;
        }
        return stakingContract.stakes(account).amount;
    }

    // ------------------------------------------------------------
    // PROPOSAL VALIDATION HOOK (optional)
    // ------------------------------------------------------------
    function proposalThreshold() public pure override returns (uint256) {
        // Minimum votes required to submit a proposal (can be adjusted)
        return 10e18;
    }

    // ------------------------------------------------------------
    // REQUIRED OVERRIDES FOR TIMLOCK
    // ------------------------------------------------------------
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
