// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVesting {
    function setVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration
    ) external;
}

interface IRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint, uint, uint);
}

/**
 * @title LaunchpadSale
 * @notice Token sale contract for projects using Atlas Launchpad.
 * - Vesting is mandatory
 * - Liquidity add is mandatory on finalize
 */
contract LaunchpadSale is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;           // Token being sold
    IERC20 public paymentToken;    // USDC/WETH/etc.

    address public projectOwner;   // Project owner
    uint256 public price;          // paymentToken per token (scaled)
    uint256 public hardcap;        // Max tokens for sale
    uint256 public sold;           // Tokens sold

    uint8 public tgePercent;       // % released at TGE
    address public vesting;        // Vesting contract (mandatory)

    address public router;         // AtlasRouter
    address public vault;          // Vault admin
    bool public finalized;         // Sale finalized

    mapping(address => uint256) public contributed;
    mapping(address => uint256) public allocated;

    event Bought(address indexed buyer, uint256 payAmount, uint256 tokenAmount);
    event Finalized(uint256 liquidityToken, uint256 liquidityPayment);

    constructor(
        address _owner,
        address _token,
        address _paymentToken,
        uint256 _price,
        uint256 _hardcap,
        uint8 _tgePercent,
        address _vesting,
        address _router,
        address _vault
    ) {
        require(_owner != address(0), "LaunchpadSale: zero owner");
        require(_token != address(0) && _paymentToken != address(0), "LaunchpadSale: zero token");
        require(_vesting != address(0), "LaunchpadSale: vesting required");
        require(_router != address(0), "LaunchpadSale: router required");
        require(_vault != address(0), "LaunchpadSale: vault required");

        projectOwner = _owner;
        token = IERC20(_token);
        paymentToken = IERC20(_paymentToken);
        price = _price;
        hardcap = _hardcap;
        tgePercent = _tgePercent;
        vesting = _vesting;
        router = _router;
        vault = _vault;

        _transferOwnership(_owner);
    }

    /// @notice Buy tokens from the sale
    function buy(uint256 payAmount) external {
        require(!finalized, "LaunchpadSale: sale closed");
        require(payAmount > 0, "LaunchpadSale: zero payment");

        uint256 tokenAmount = (payAmount * 1e18) / price;
        require(sold + tokenAmount <= hardcap, "LaunchpadSale: hardcap reached");

        paymentToken.safeTransferFrom(msg.sender, address(this), payAmount);
        contributed[msg.sender] += payAmount;
        allocated[msg.sender] += tokenAmount;
        sold += tokenAmount;

        emit Bought(msg.sender, payAmount, tokenAmount);
    }

    /**
     * @notice Finalize the sale
     * - Transfer all payments to vault
     * - Must add liquidity to AtlasRouter
     */
    function finalize(
        uint256 liquidityTokenAmount,
        uint256 liquidityPayAmount,
        uint256 minTok,
        uint256 minPay,
        uint256 deadline
    ) external onlyOwner {
        require(!finalized, "LaunchpadSale: already finalized");

        // Transfer all payments to vault
        uint256 balance = paymentToken.balanceOf(address(this));
        if (balance > 0) {
            paymentToken.safeTransfer(vault, balance);
        }

        // Add liquidity (mandatory)
        require(token.balanceOf(address(this)) >= liquidityTokenAmount, "LaunchpadSale: insufficient token");
        token.safeApprove(router, liquidityTokenAmount);
        paymentToken.safeApprove(router, liquidityPayAmount);

        IRouter(router).addLiquidity(
            address(token),
            address(paymentToken),
            liquidityTokenAmount,
            liquidityPayAmount,
            minTok,
            minPay,
            projectOwner,
            deadline
        );

        emit Finalized(liquidityTokenAmount, liquidityPayAmount);
        finalized = true;
    }

    /// @notice Claim allocated tokens (TGE + vesting)
    function claim() external {
        require(finalized, "LaunchpadSale: not finalized");
        uint256 amount = allocated[msg.sender];
        require(amount > 0, "LaunchpadSale: no allocation");

        allocated[msg.sender] = 0;

        // TGE allocation
        uint256 tgeAmount = (amount * tgePercent) / 100;
        token.safeTransfer(msg.sender, tgeAmount);

        // Vesting remainder (mandatory)
        uint256 rest = amount - tgeAmount;
        IVesting(vesting).setVestingSchedule(msg.sender, rest, block.timestamp, 0, 30 days);
    }

    /// @notice Fund sale with tokens
    function fundSale(uint256 tokenAmount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
    }
}
