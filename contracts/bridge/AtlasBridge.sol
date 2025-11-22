// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AtlasToken.sol";
import "../utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AtlasBridge
 * @notice Handles cross-chain token bridging: lock on source chain, mint on target chain.
 *         Uses SafeERC20 to prevent token transfer failures.
 */
contract AtlasBridge is Ownable {
    using SafeERC20 for IERC20;

    AtlasToken public token;

    event Locked(address indexed user, uint256 amount, string targetChain);
    event Minted(address indexed user, uint256 amount);
    event BridgeTokenUpdated(address indexed oldToken, address indexed newToken);

    constructor(AtlasToken _token) {
        require(address(_token) != address(0), "Invalid token");
        token = _token;
    }

    /**
     * @notice Lock tokens to bridge to another chain
     * @param amount Amount of tokens to lock
     * @param targetChain Name of the target chain
     */
    function lock(uint256 amount, string calldata targetChain) external {
        require(amount > 0, "Amount must be > 0");
        require(bytes(targetChain).length > 0, "Invalid target chain");

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(msg.sender, amount, targetChain);
    }

    /**
     * @notice Mint tokens for users coming from another chain
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");

        token.bridgeMint(to, amount);

        emit Minted(to, amount);
    }

    /**
     * @notice Update the token used by the bridge
     * @param newToken New AtlasToken address
     */
    function updateToken(AtlasToken newToken) external onlyOwner {
        require(address(newToken) != address(0), "Invalid token");
        address old = address(token);
        token = newToken;
        emit BridgeTokenUpdated(old, address(newToken));
    }

    /**
     * @notice Batch lock multiple amounts for multiple chains (optional multicall-friendly)
     * @param users Array of user addresses
     * @param amounts Array of amounts
     * @param targetChains Array of target chains
     */
    function batchLock(
        address[] calldata users,
        uint256[] calldata amounts,
        string[] calldata targetChains
    ) external {
        require(users.length == amounts.length && users.length == targetChains.length, "Array length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            require(amounts[i] > 0, "Amount must be > 0");
            require(users[i] != address(0), "Invalid user");
            require(bytes(targetChains[i]).length > 0, "Invalid target chain");

            token.safeTransferFrom(msg.sender, address(this), amounts[i]);
            emit Locked(users[i], amounts[i], targetChains[i]);
        }
    }
}
