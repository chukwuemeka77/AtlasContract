// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AtlasToken.sol";
import "../utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/Multicall.sol";

contract AtlasBridge is Ownable, Multicall {
    using SafeERC20 for IERC20;

    AtlasToken public token;

    event Locked(address indexed user, uint256 amount, string targetChain);
    event Minted(address indexed user, uint256 amount);
    event Burned(address indexed user, uint256 amount);

    constructor(AtlasToken _token) {
        token = _token;
    }

    /// @notice Lock tokens for bridging to another chain
    function lock(uint256 amount, string calldata targetChain) external {
        IERC20(address(token)).safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, targetChain);
    }

    /// @notice Mint tokens on this chain (only owner / bridge)
    function mint(address to, uint256 amount) external onlyOwner {
        token.bridgeMint(to, amount);
        emit Minted(to, amount);
    }

    /// @notice Burn tokens (for bridging out)
    function burn(uint256 amount) external {
        token.bridgeBurn(msg.sender, amount);
        emit Burned(msg.sender, amount);
    }
}
