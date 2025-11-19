// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/SafeERC20.sol";
import "./Vesting.sol";

/**
 * @title Presale
 * @notice Conducts token presale and deposits tokens into vesting.
 */
contract Presale is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public saleToken;
    IERC20 public paymentToken; // e.g., USDC
    Vesting public vesting;
    uint256 public price; // paymentToken per saleToken

    mapping(address => uint256) public purchased;

    event Purchased(address indexed buyer, uint256 amountPaid, uint256 tokensAllocated);

    constructor(
        address _saleToken,
        address _paymentToken,
        address _vesting,
        uint256 _price,
        address _owner
    ) {
        saleToken = IERC20(_saleToken);
        paymentToken = IERC20(_paymentToken);
        vesting = Vesting(_vesting);
        price = _price;
        transferOwnership(_owner);
    }

    function buy(uint256 paymentAmount) external {
        uint256 tokenAmount = (paymentAmount * 1e18) / price;
        paymentToken.safeTransferFrom(msg.sender, address(this), paymentAmount);
        vesting.setVestingSchedule(msg.sender, tokenAmount, block.timestamp, 0, 30 days); // simple 30-day linear vesting
        purchased[msg.sender] += tokenAmount;
        emit Purchased(msg.sender, paymentAmount, tokenAmount);
    }

    function withdrawPayment(address to) external onlyOwner {
        paymentToken.safeTransfer(to, paymentToken.balanceOf(address(this)));
    }
}
