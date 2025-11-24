// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

contract LaunchpadSale is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    IERC20 public paymentToken;
    address public projectOwner;
    uint256 public price;          // paymentToken per token
    uint256 public hardcap;        // max tokens for sale
    uint256 public sold;           // total tokens sold
    uint8 public tgePercent;       // percent released at TGE
    uint256 public vestingDuration; // optional vesting
    bool public autoAddLiquidity;   // optional liquidity add
    address public router;           // router address for liquidity
    address public vault;            // treasury address
    bool public finalized;

    mapping(address => uint256) public contributed;
    mapping(address => uint256) public allocated;
    mapping(address => uint256) public claimed; // track claimed tokens for vesting

    uint256 public startTime;

    event Bought(address indexed buyer, uint256 payAmount, uint256 tokenAmount);
    event Finalized(uint256 liquidityToken, uint256 liquidityPayment);

    constructor(
        address _owner,
        address _token,
        address _paymentToken,
        uint256 _price,
        uint256 _hardcap,
        uint8 _tgePercent,
        uint256 _vestingDuration,
        bool _autoAddLiquidity,
        address _router,
        address _vault
    ) {
        require(_owner != address(0), "zero owner");
        require(_token != address(0), "zero token");
        require(_paymentToken != address(0), "zero payment");

        projectOwner = _owner;
        token = IERC20(_token);
        paymentToken = IERC20(_paymentToken);
        price = _price;
        hardcap = _hardcap;
        tgePercent = _tgePercent;
        vestingDuration = _vestingDuration;
        autoAddLiquidity = _autoAddLiquidity;
        router = _router;
        vault = _vault;

        _transferOwnership(_owner);
        startTime = block.timestamp;
    }

    function buy(uint256 payAmount) external {
        require(!finalized, "sale closed");
        require(payAmount > 0, "zero pay");

        uint256 tokenAmount = (payAmount * 1e18) / price; // scaled calculation
        require(sold + tokenAmount <= hardcap, "cap reached");

        paymentToken.safeTransferFrom(msg.sender, address(this), payAmount);
        contributed[msg.sender] += payAmount;
        allocated[msg.sender] += tokenAmount;
        sold += tokenAmount;

        emit Bought(msg.sender, payAmount, tokenAmount);
    }

    function finalize(
        uint256 liquidityTokenAmount,
        uint256 liquidityPayAmount,
        uint256 minTok,
        uint256 minPay,
        uint256 deadline
    ) external onlyOwner {
        require(!finalized, "already finalized");

        // Transfer payment to vault
        uint256 balance = paymentToken.balanceOf(address(this));
        if (balance > 0) {
            paymentToken.safeTransfer(vault, balance);
        }

        // Optional liquidity add
        if (autoAddLiquidity) {
            require(token.balanceOf(address(this)) >= liquidityTokenAmount, "not enough token");
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
        }

        finalized = true;
    }

    function claim() external {
        require(finalized, "not finalized");
        uint256 totalAllocated = allocated[msg.sender];
        require(totalAllocated > 0, "no allocation");

        uint256 tgeAmount = (totalAllocated * tgePercent) / 100;
        uint256 vestAmount = totalAllocated - tgeAmount;

        allocated[msg.sender] = 0;
        claimed[msg.sender] = vestAmount;

        // Send TGE
        if (tgeAmount > 0) {
            token.safeTransfer(msg.sender, tgeAmount);
        }

        // Vesting (optional)
        if (vestingDuration == 0 && vestAmount > 0) {
            token.safeTransfer(msg.sender, vestAmount); // immediate if no vesting
            claimed[msg.sender] = 0;
        }
        // If vesting exists, tokens remain in contract and can be claimed later
    }

    function claimVested() external {
        require(vestingDuration > 0, "no vesting configured");
        uint256 vestBalance = claimed[msg.sender];
        require(vestBalance > 0, "nothing to claim");

        uint256 elapsed = block.timestamp - startTime;
        uint256 claimable = (vestBalance * elapsed) / vestingDuration;
        if (claimable > vestBalance) claimable = vestBalance;

        claimed[msg.sender] -= claimable;
        token.safeTransfer(msg.sender, claimable);
    }

    // Admin: fund contract with tokens for sale/vesting
    function fundSale(uint256 tokenAmount) external {
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
    }
}
