// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Upgradeable RewardDistributor (UUPS)
  - initialize() instead of constructor
  - owner (OwnableUpgradeable) controls recipients & distribution
  - parts-per-million (ppm) shares for precision
  - SafeERC20 transfers
*/

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RewardDistributorUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;

  IERC20 public feeToken;
  address public feeCollector;

  uint256 public constant PPM_BASE = 1_000_000;

  struct Recipient {
    address account;
    uint256 share; // ppm
    bool exists;
  }

  address[] private recipientList;
  mapping(address => Recipient) private recipients;
  uint256 public totalShares; // ppm sum

  event FeeTokenSet(address indexed token);
  event FeeCollectorSet(address indexed collector);
  event RecipientAdded(address indexed account, uint256 share);
  event RecipientRemoved(address indexed account);
  event RecipientShareUpdated(address indexed account, uint256 newShare);
  event FeesDeposited(address indexed from, uint256 amount);
  event Distributed(uint256 totalAmount, uint256 timestamp);
  event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  function initialize(address _feeToken, address _feeCollector, address _owner) external initializer {
    require(_feeToken != address(0), "invalid token");
    __Ownable_init();
    __UUPSUpgradeable_init();
    feeToken = IERC20(_feeToken);
    feeCollector = _feeCollector;
    if (_owner != address(0)) {
      transferOwnership(_owner);
    }
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  // Admin setters
  function setFeeToken(address _token) external onlyOwner {
    require(_token != address(0), "zero token");
    feeToken = IERC20(_token);
    emit FeeTokenSet(_token);
  }

  function setFeeCollector(address _collector) external onlyOwner {
    feeCollector = _collector;
    emit FeeCollectorSet(_collector);
  }

  // Recipient management
  function addRecipient(address _account, uint256 _share) external onlyOwner {
    require(_account != address(0), "zero account");
    require(!recipients[_account].exists, "exists");
    require(_share > 0, "share=0");
    recipients[_account] = Recipient({account: _account, share: _share, exists: true});
    recipientList.push(_account);
    totalShares += _share;
    require(totalShares <= PPM_BASE, "total > 100%");
    emit RecipientAdded(_account, _share);
  }

  function removeRecipient(address _account) external onlyOwner {
    require(recipients[_account].exists, "not exists");
    uint256 s = recipients[_account].share;
    totalShares -= s;
    delete recipients[_account];

    // swap & pop
    for (uint i = 0; i < recipientList.length; i++) {
      if (recipientList[i] == _account) {
        recipientList[i] = recipientList[recipientList.length - 1];
        recipientList.pop();
        break;
      }
    }
    emit RecipientRemoved(_account);
  }

  function updateShare(address _account, uint256 _newShare) external onlyOwner {
    require(recipients[_account].exists, "not exists");
    require(_newShare > 0, "zero");
    uint256 old = recipients[_account].share;
    recipients[_account].share = _newShare;
    totalShares = totalShares - old + _newShare;
    require(totalShares <= PPM_BASE, "total > 100%");
    emit RecipientShareUpdated(_account, _newShare);
  }

  // deposit (push)
  function depositFees(uint256 amount) external {
    require(amount > 0, "amount=0");
    if (feeCollector != address(0)) {
      require(msg.sender == feeCollector, "not collector");
    }
    feeToken.safeTransferFrom(msg.sender, address(this), amount);
    emit FeesDeposited(msg.sender, amount);
  }

  // Distribute all balance according to shares
  function distribute() external onlyOwner {
    uint256 balance = feeToken.balanceOf(address(this));
    require(balance > 0, "no fees");
    require(recipientList.length > 0, "no recipients");

    uint256 distributed = 0;
    for (uint i = 0; i < recipientList.length; i++) {
      address acc = recipientList[i];
      Recipient memory r = recipients[acc];
      if (!r.exists || r.share == 0) continue;
      uint256 amt = (balance * r.share) / PPM_BASE;
      if (amt > 0) {
        feeToken.safeTransfer(r.account, amt);
        distributed += amt;
      }
    }

    uint256 leftover = balance - distributed;
    if (leftover > 0) {
      feeToken.safeTransfer(owner(), leftover); // leftover to owner to avoid stranded dust
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

  // Rescue
  function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
    require(to != address(0), "zero to");
    if (token == address(0)) {
      (bool ok, ) = to.call{value: amount}("");
      require(ok, "eth transfer failed");
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
    emit EmergencyWithdraw(token, to, amount);
  }

  receive() external payable {}
}
