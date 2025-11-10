// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Bridge contract (EVM-side)
  - lockToken: user deposits native token to this contract to bridge out
             (emits TokenLocked event for relayer to observe)
  - mintWrapped: called by relayer/multisig to mint wrapped token on this chain
  - burnWrapped: user burns wrapped token to move back to native chain
  - unlockToken: relayer/multisig unlocks previously locked tokens (after burn on other chain)

  Events: TokenLocked, TokenMinted, TokenBurned, TokenUnlocked
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Bridge is AccessControl {
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    event TokenLocked(
      address indexed user,
      address indexed token,
      uint256 amount,
      string toChain,
      string toAddress,
      bytes32 indexed nonce
    );

    event TokenMinted(
      address indexed to,
      address indexed token,
      uint256 amount,
      string fromChain,
      bytes32 indexed nonce,
      string txHash
    );

    event TokenBurned(
      address indexed user,
      address indexed token,
      uint256 amount,
      string toChain,
      string toAddress,
      bytes32 indexed nonce
    );

    event TokenUnlocked(
      address indexed to,
      address indexed token,
      uint256 amount,
      bytes32 indexed nonce,
      string txHash
    );

    // keep track to prevent replay
    mapping(bytes32 => bool) public processed;

    constructor(address admin) {
        _setupRole(ADMIN_ROLE, admin);
    }

    // user calls to lock tokens on this chain to bridge to another chain
    function lockToken(
        address token,
        uint256 amount,
        string calldata toChain,
        string calldata toAddress,
        bytes32 nonce
    ) external {
        require(!processed[nonce], "nonce processed");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "transfer failed");
        processed[nonce] = true;

        emit TokenLocked(msg.sender, token, amount, toChain, toAddress, nonce);
    }

    // relayer mints wrapped tokens on this chain (token must be AtlasToken or wrapped representation)
    function mintWrapped(
        address token,
        address to,
        uint256 amount,
        string calldata fromChain,
        bytes32 nonce,
        string calldata sourceTxHash
    ) external onlyRole(RELAYER_ROLE) {
        bytes32 key = keccak256(abi.encodePacked("mint", token, to, amount, fromChain, nonce));
        require(!processed[key], "already processed");
        processed[key] = true;

        // token is expected to be ERC20 with mint capability via minter role
        // We attempt to call a known mint interface (AtlasToken)
        (bool ok, bytes memory res) = token.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        require(ok, "mint failed");

        emit TokenMinted(to, token, amount, fromChain, nonce, sourceTxHash);
    }

    // user burns wrapped tokens on this chain to retrieve native tokens on another chain
    function burnWrapped(
        address token,
        uint256 amount,
        string calldata toChain,
        string calldata toAddress,
        bytes32 nonce
    ) external {
        require(!processed[nonce], "nonce processed");
        // assume token implements burnFrom or burn (AtlasToken allows burnSelf)
        // We will try burnFrom first, fallback to transfer to contract + mark
        // For safety, require token has burn function via interface call
        (bool ok, ) = token.call(abi.encodeWithSignature("burn(address,uint256)", msg.sender, amount));
        require(ok, "burn failed");

        processed[nonce] = true;
        emit TokenBurned(msg.sender, token, amount, toChain, toAddress, nonce);
    }

    // relayer unlock tokens previously locked on this chain after seeing burn on other chain
    function unlockToken(
        address token,
        address to,
        uint256 amount,
        bytes32 nonce,
        string calldata sourceTxHash
    ) external onlyRole(RELAYER_ROLE) {
        bytes32 key = keccak256(abi.encodePacked("unlock", token, to, amount, nonce));
        require(!processed[key], "already processed");
        processed[key] = true;

        require(IERC20(token).transfer(to, amount), "transfer failed");
        emit TokenUnlocked(to, token, amount, nonce, sourceTxHash);
    }
}

