// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AtlasVesting is Ownable {
    struct VestingSchedule {
        uint256 totalAllocation;
        uint256 claimed;
        uint64 startTime;
        uint64 cliffTime;
        uint64 endTime;
        bool initialized;
    }

    IERC20 public immutable atlasToken;

    mapping(address => VestingSchedule) public vestings;

    event VestingCreated(
        address indexed beneficiary,
        uint256 totalAllocation,
        uint64 startTime,
        uint64 cliffTime,
        uint64 endTime
    );

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingUpdated(address indexed beneficiary, uint256 newAmount);
    event VestingRevoked(address indexed beneficiary);

    constructor(address _atlasToken) Ownable(msg.sender) {
        require(_atlasToken != address(0), "Invalid token");
        atlasToken = IERC20(_atlasToken);
    }

    // ------------------------------------------------------------
    // ADMIN: Create vesting schedule
    // ------------------------------------------------------------
    function createVesting(
        address beneficiary,
        uint256 totalAllocation,
        uint64 startTime,
        uint64 cliffTime,
        uint64 endTime
    ) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(!vestings[beneficiary].initialized, "Vesting exists");
        require(startTime < endTime, "Invalid time range");
        require(cliffTime >= startTime, "Cliff before start");

        vestings[beneficiary] = VestingSchedule({
            totalAllocation: totalAllocation,
            claimed: 0,
            startTime: startTime,
            cliffTime: cliffTime,
            endTime: endTime,
            initialized: true
        });

        emit VestingCreated(beneficiary, totalAllocation, startTime, cliffTime, endTime);
    }

    // ------------------------------------------------------------
    // ADMIN: Batch create vestings for team/advisors/investors
    // ------------------------------------------------------------
    function batchCreateVestings(
        address[] calldata beneficiaries,
        uint256[] calldata allocations,
        uint64 startTime,
        uint64 cliffTime,
        uint64 endTime
    ) external onlyOwner {
        require(beneficiaries.length == allocations.length, "Length mismatch");

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            createVesting(
                beneficiaries[i],
                allocations[i],
                startTime,
                cliffTime,
                endTime
            );
        }
    }

    // ------------------------------------------------------------
    // CLAIM: Users claim vested tokens
    // ------------------------------------------------------------
    function claim() external {
        VestingSchedule storage vesting = vestings[msg.sender];
        require(vesting.initialized, "No vesting");
        require(block.timestamp >= vesting.cliffTime, "Cliff not reached");

        uint256 vested = _vestedAmount(vesting);
        uint256 claimable = vested - vesting.claimed;
        require(claimable > 0, "Nothing to claim");

        vesting.claimed += claimable;
        atlasToken.transfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    // ------------------------------------------------------------
    // INTERNAL: Calculate vested amount at current time
    // ------------------------------------------------------------
    function _vestedAmount(VestingSchedule memory vesting)
        internal
        view
        returns (uint256)
    {
        if (block.timestamp < vesting.cliffTime) {
            return 0;
        }

        if (block.timestamp >= vesting.endTime) {
            return vesting.totalAllocation;
        }

        uint256 duration = vesting.endTime - vesting.startTime;
        uint256 timePassed = block.timestamp - vesting.startTime;

        return (vesting.totalAllocation * timePassed) / duration;
    }

    // ------------------------------------------------------------
    // VIEW: Claimable tokens
    // ------------------------------------------------------------
    function claimable(address beneficiary) external view returns (uint256) {
        VestingSchedule memory vesting = vestings[beneficiary];
        uint256 vested = _vestedAmount(vesting);
        return vested - vesting.claimed;
    }

    // ------------------------------------------------------------
    // ADMIN: Revoke vesting (unused tokens stay in contract)
    // Rarely needed but included for safety
    // ------------------------------------------------------------
    function revoke(address beneficiary) external onlyOwner {
        require(vestings[beneficiary].initialized, "No vesting");
        delete vestings[beneficiary];
        emit VestingRevoked(beneficiary);
    }
}
