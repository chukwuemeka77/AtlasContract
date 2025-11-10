// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  RewardDistributor.sol
  - Collects protocol fees (in a specified fee token) and distributes them to recipients based on shares.
  - Owner (admin) can add/remove recipients, change shares, set feeToken, set feeCollector, and trigger distribution.
  - Uses SafeERC20 for safe transfers.
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardDistributor is Ownable {
  using SafeERC20 for IERC20;

  // Fee token (e.g., USDT, USDC, or Atlas token) used to collect protocol fees
  IERC20 public feeToken;

  // Address allowed to deposit fees (optional); default = anyone
  address public feeCollector;

  // Recipient structure
  struct Recipient {
    address account;
    uint256 share; // parts per million (ppm) for precision, e.g., 100_000 = 10%
    bool exists;
  }

  // list + mapping
  address[] public recipientList;
  mapping(address => Recipient) public recipients;

  // total shares in ppm (max 1_000_000)
  uint256 public totalShares; // ppm scale

  // Events
  event FeeTokenSet(address indexed token);
  event FeeCollectorSet(address indexed collector);
  event RecipientAdded(address indexed account, uint256 share);
  event RecipientRemoved(address indexed account);
  event RecipientShareUpdated(address indexed account, uint256 newShare);
  event FeesDeposited(address indexed from, uint256 amount);
  event Distributed(uint256 totalAmount, uint256 timestamp);
  event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

  // ppm base (1_000_000 = 100%)
  uint256 public constant PPM_BASE = 1_000_000;

  constructor(address _feeToken, address _feeCollector) {
    require(_feeToken != address(0), "Invalid fee token");
    feeToken = IERC20(_feeToken);
    feeCollector = _feeCollector;
  }

  // ----- admin functions -----
  function setFeeToken(address _token) external onlyOwner {
    require(_token != address(0), "zero token");
    feeToken = IERC20(_token);
    emit FeeTokenSet(_token);
  }

  function setFeeCollector(address _collector) external onlyOwner {
    feeCollector = _collector;
    emit FeeCollectorSet(_collector);
  }

  // Add recipient (account must not exist)
  function addRecipient(address _account, uint256 _share) external onlyOwner {
    require(_account != address(0), "zero account");
    require(!recipients[_account].exists, "recipient exists");
    require(_share > 0, "share=0");
    recipients[_account] = Recipient({account: _account, share: _share, exists: true});
    recipientList.push(_account);
    totalShares += _share;
    require(totalShares <= PPM_BASE, "total > 100%");
    emit RecipientAdded(_account, _share);
  }

  // Remove recipient
  function removeRecipient(address _account) external onlyOwner {
    require(recipients[_account].exists, "not exists");
    uint256 share = recipients[_account].share;
    totalShares -= share;
    delete recipients[_account];

    // remove from array (swap & pop)
    for (uint i = 0; i < recipientList.length; i++) {
      if (recipientList[i] == _account) {
        recipientList[i] = recipientList[recipientList.length - 1];
        recipientList.pop();
        break;
      }
    }
    emit RecipientRemoved(_account);
  }

  // Update share for an existing recipient
  function updateShare(address _account, uint256 _newShare) external onlyOwner {
    require(recipients[_account].exists, "not exists");
    require(_newShare > 0, "share=0");
    uint256 old = recipients[_account].share;
    recipients[_account].share = _newShare;
    totalShares = totalShares - old + _newShare;
    require(totalShares <= PPM_BASE, "total > 100%");
    emit RecipientShareUpdated(_account, _newShare);
  }

  // ----- operational functions -----
  // Deposit fees into the contract (push model). If feeCollector is set, only that address can call.
  function depositFees(uint256 amount) external {
    require(amount > 0, "amount=0");
    if (feeCollector != address(0)) require(msg.sender == feeCollector, "not feeCollector");
    feeToken.safeTransferFrom(msg.sender, address(this), amount);
    emit FeesDeposited(msg.sender, amount);
  }

  // Distribute all collected fees per shares
  function distribute() external onlyOwner {
    uint256 balance = feeToken.balanceOf(address(this));
    require(balance > 0, "no fees");

    // If no recipients configured, revert (or optionally send to owner)
    require(recipientList.length > 0, "no recipients");

    // distribute
    uint256 distributed = 0;
    for (uint i = 0; i < recipientList.length; i++) {
      address acc = recipientList[i];
      Recipient memory r = recipients[acc];
      if (!r.exists || r.share == 0) continue;
      uint256 amount = (balance * r.share) / PPM_BASE;
      if (amount > 0) {
        feeToken.safeTransfer(r.account, amount);
        distributed += amount;
      }
    }

    // If rounding leftover, send to owner (admin) or keep; here we send to owner
    uint256 leftover = balance - distributed;
    if (leftover > 0) {
      feeToken.safeTransfer(owner(), leftover);
    }

    emit Distributed(balance, block.timestamp);
  }

  // view helpers
  function recipientsCount() external view returns (uint256) {
    return recipientList.length;
  }

  function getRecipientAt(uint256 idx) external view returns (address, uint256) {
    address acc = recipientList[idx];
    return (acc, recipients[acc].share);
  }

  // Emergency rescue (only owner)
  function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
    require(to != address(0), "zero to");
    if (token == address(0)) {
      // withdraw native ETH (if ever used)
      (bool ok, ) = to.call{value: amount}("");
      require(ok, "eth transfer failed");
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
    emit EmergencyWithdraw(token, to, amount);
  }

  // Accept ETH if needed
  receive() external payable {}
}
