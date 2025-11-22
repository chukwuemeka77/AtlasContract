// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/SafeERC20.sol";
import "../utils/Multicall.sol";

interface IVesting {
    function setVestingSchedule(address, uint256, uint256, uint256, uint256) external;
}

contract Presale is Ownable, Multicall {
    using SafeERC20 for IERC20;

    IERC20 public token;
    IERC20 public paymentToken; // USDC or ETH wrapper
    IVesting public vesting;

    uint256 public price; // price per token in paymentToken
    uint256 public sold;
    uint256 public maxAllocation;

    event Purchased(address indexed buyer, uint256 amount, uint256 cost);

    constructor(
        address _token,
        address _vesting,
        address _paymentToken,
        uint256 _price,
        uint256 _maxAllocation
    ) {
        token = IERC20(_token);
        vesting = IVesting(_vesting);
        paymentToken = IERC20(_paymentToken);
        price = _price;
        maxAllocation = _maxAllocation;
    }

    /// @notice Buy tokens in presale
    function buy(uint256 tokenAmount) external {
        require(sold + tokenAmount <= maxAllocation, "Exceeds max allocation");
        uint256 cost = (tokenAmount * price) / (10 ** 18); // assumes 18 decimals
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);
        sold += tokenAmount;

        // Set vesting schedule for buyer
        uint256 start = block.timestamp;
        uint256 cliff = 0;
        uint256 duration = 30 days; // simple example
        vesting.setVestingSchedule(msg.sender, tokenAmount, start, cliff, duration);
        emit Purchased(msg.sender, tokenAmount, cost);
    }

    /// @notice Admin can withdraw collected payment tokens
    function withdrawPayments(address to, uint256 amount) external onlyOwner {
        paymentToken.safeTransfer(to, amount);
    }
}
