// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Vesting.sol";
import "../utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Presale is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    Vesting public vesting;
    IERC20 public paymentToken;
    uint256 public price;
    uint256 public maxAllocation;

    event Purchased(address indexed buyer, uint256 amount);

    constructor(
        address _token,
        address _vesting,
        address _paymentToken,
        uint256 _price,
        uint256 _maxAllocation
    ) {
        token = IERC20(_token);
        vesting = Vesting(_vesting);
        paymentToken = IERC20(_paymentToken);
        price = _price;
        maxAllocation = _maxAllocation;
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    function setVesting(address _vesting) external onlyOwner {
        require(_vesting != address(0), "Invalid vesting");
        vesting = Vesting(_vesting);
    }

    function buy(uint256 amount) external {
        require(amount <= maxAllocation, "Exceeds max allocation");
        uint256 cost = (amount * price) / (10**18);
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);

        // send tokens to vesting schedule
        token.safeTransfer(address(vesting), amount);
        vesting.setVestingSchedule(msg.sender, amount, block.timestamp, 0, 30 days);

        emit Purchased(msg.sender, amount);
    }
}
