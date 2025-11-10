// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeCollector is Ownable {
    event FeeCollected(address indexed token, uint256 amount);
    event FeeWithdrawn(address indexed to, address indexed token, uint256 amount);

    function collectFee(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit FeeCollected(token, amount);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
        emit FeeWithdrawn(to, token, amount);
    }
}
