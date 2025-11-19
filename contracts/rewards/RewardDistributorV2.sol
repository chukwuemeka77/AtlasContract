// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 RewardDistributorV2.sol

 - Collects feeToken (e.g., USDC or ATLAS) into this contract.
 - Distributes balances to:
     1) LP reward sink (contract)  -- receives notifyRewardAmount(uint256)
     2) Staking reward sink (contract) -- receives notifyRewardAmount(uint256)
     3) AtlasVault (treasury / bridge sink) -- receives plain ERC20 transfer
 - Shares are in PPM (parts-per-million) for precision (1_000_000 = 100%).
 - Uses an ownership model where the deployer (or multisig) is the initial owner.
 - Anyone (relayer/keeper) may call distribute() but must respect minDistributionInterval.
*/

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRewardSink {
    /// @notice Called by the distributor when new rewards are available
    function notifyRewardAmount(uint256 amount) external;
}

contract RewardDistributorV2 is Ownable {
    using SafeERC20 for IERC20;

    // ---- constants ----
    uint256 public constant PPM_BASE = 1_000_000;

    // ---- state ----
    IERC20 public feeToken;              // token used for fees & distributions
    address public lpRewardSink;         // contract that handles LP rewards (must implement IRewardSink)
    address public stakingRewardSink;    // contract that handles staking rewards (must implement IRewardSink)
    address public vault;                // AtlasVault / treasury address (receives direct transfers / bridge fees)

    // shares in ppm
    uint256 public lpSharePpm;        // e.g., 200_000 = 20%
    uint256 public stakingSharePpm;   // e.g., 100_000 = 10%
    // vaultSharePpm is computed as remainder: PPM_BASE - lp - staking

    // distribution interval control (seconds)
    uint256 public minDistributionInterval = 3600; // default 1 hour
    uint256 public lastDistributionTimestamp;

    // events
    event FeeTokenSet(address indexed token);
    event VaultSet(address indexed vault);
    event SinksUpdated(address indexed lpSink, address indexed stakingSink);
    event SharesUpdated(uint256 lpSharePpm, uint256 stakingSharePpm);
    event Distribution(uint256 totalAmount, uint256 lpAmount, uint256 stakingAmount, uint256 vaultAmount, uint256 timestamp);
    event MinIntervalSet(uint256 seconds);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event FeesDeposited(address indexed from, uint256 amount);

    // ---- modifiers ----
    modifier ensureSharesSafe(uint256 _lpPpm, uint256 _stakingPpm) {
        require(_lpPpm + _stakingPpm <= PPM_BASE, "Shares > 100%");
        _;
    }

    /// @dev constructor accepts an owner for Ownable(initialOwner)
    constructor(address _owner, address _feeToken, address _vault, uint256 _lpSharePpm, uint256 _stakingSharePpm)
        Ownable(_owner)
        ensureSharesSafe(_lpSharePpm, _stakingSharePpm)
    {
        require(_feeToken != address(0), "zero feeToken");
        require(_vault != address(0), "zero vault");
        feeToken = IERC20(_feeToken);
        vault = _vault;

        lpSharePpm = _lpSharePpm;
        stakingSharePpm = _stakingSharePpm;

        emit FeeTokenSet(_feeToken);
        emit VaultSet(_vault);
        emit SharesUpdated(_lpSharePpm, _stakingSharePpm);
    }

    // ----------- Admin / Config -----------
    function setFeeToken(address _token) external onlyOwner {
        require(_token != address(0), "zero token");
        feeToken = IERC20(_token);
        emit FeeTokenSet(_token);
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "zero vault");
        vault = _vault;
        emit VaultSet(_vault);
    }

    function setSinks(address _lpSink, address _stakingSink) external onlyOwner {
        lpRewardSink = _lpSink;
        stakingRewardSink = _stakingSink;
        emit SinksUpdated(_lpSink, _stakingSink);
    }

    function setShares(uint256 _lpSharePpm, uint256 _stakingSharePpm) external onlyOwner ensureSharesSafe(_lpSharePpm, _stakingSharePpm) {
        lpSharePpm = _lpSharePpm;
        stakingSharePpm = _stakingSharePpm;
        emit SharesUpdated(_lpSharePpm, _stakingSharePpm);
    }

    function setMinDistributionInterval(uint256 _seconds) external onlyOwner {
        minDistributionInterval = _seconds;
        emit MinIntervalSet(_seconds);
    }

    // ----------- Operational / Deposit -----------
    /// @notice deposit fees to this contract (push model)
    function depositFees(uint256 amount) external {
        require(amount > 0, "amount=0");
        feeToken.safeTransferFrom(msg.sender, address(this), amount);
        emit FeesDeposited(msg.sender, amount);
    }

    // ----------- Distribution Logic -----------
    /// @notice distribute collected fees according to ppm shares
    /// Anyone (relayer / keeper / owner) can call; minDistributionInterval enforced
    function distribute() external {
        require(block.timestamp >= lastDistributionTimestamp + minDistributionInterval, "too soon");

        uint256 balance = feeToken.balanceOf(address(this));
        require(balance > 0, "no fees");

        // compute amounts
        uint256 lpAmount = (balance * lpSharePpm) / PPM_BASE;
        uint256 stakingAmount = (balance * stakingSharePpm) / PPM_BASE;
        uint256 vaultAmount = balance - lpAmount - stakingAmount; // remainder to vault

        // deliver to LP sink
        if (lpAmount > 0 && lpRewardSink != address(0)) {
            // try to call notifyRewardAmount on sink; if sink is zero or does not support interface, fallback to transfer
            _safeNotifyOrTransfer(lpRewardSink, lpAmount);
        }

        // deliver to Staking sink
        if (stakingAmount > 0 && stakingRewardSink != address(0)) {
            _safeNotifyOrTransfer(stakingRewardSink, stakingAmount);
        }

        // deliver vault amount
        if (vaultAmount > 0) {
            feeToken.safeTransfer(vault, vaultAmount);
        }

        lastDistributionTimestamp = block.timestamp;
        emit Distribution(balance, lpAmount, stakingAmount, vaultAmount, block.timestamp);
    }

    /// @dev helper: if receiver is a contract that implements notifyRewardAmount(uint256),
    /// call it after transferring or, to avoid double-transfer, prefer calling notifyRewardAmount
    /// and let the sink pull funds from the distributor. We'll use a pattern:
    /// 1) try low-level call to notifyRewardAmount without transferring
    ///    -> if it returns true, then the sink is expected to pull from distributor (sink must call IERC20.transferFrom)
    /// 2) otherwise fallback to direct transfer.
    ///
    /// To keep things simple and safe, this implementation does:
    /// - Direct transfer then attempt notifyRewardAmount (best for sinks that accept direct funding + external accounting)
    function _safeNotifyOrTransfer(address sink, uint256 amount) internal {
        // direct transfer
        feeToken.safeTransfer(sink, amount);

        // then try to call notifyRewardAmount; ignore revert (not required)
        (bool ok, ) = sink.call(abi.encodeWithSignature("notifyRewardAmount(uint256)", amount));
        // ignore ok result; sinks that want notification can implement it.
        ok; // silence compilers about unused var
    }

    // ----------- Views -----------
    function vaultSharePpm() external view returns (uint256) {
        return PPM_BASE - lpSharePpm - stakingSharePpm;
    }

    // ----------- Emergency / Rescue -----------
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero to");
        if (token == address(0)) {
            // withdraw native ETH (if any)
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "eth transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit EmergencyWithdraw(token, to, amount);
    }

    // accept ETH if needed
    receive() external payable {}
}
