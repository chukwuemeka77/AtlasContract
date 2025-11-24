// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NFTStakingPool
 * @notice Stake NFTs to earn ERC20 rewards (e.g., Atlas)
 */
contract NFTStakingPool is Ownable, ReentrancyGuard {
    IERC20 public rewardToken;
    IERC721 public nftCollection;
    uint256 public rewardRatePerSecond; // reward per NFT per second

    struct Stake {
        uint256 tokenId;
        uint256 stakedAt;
        address owner;
    }

    mapping(uint256 => Stake) public stakes;
    mapping(address => uint256[]) public userStakes;

    event NFTStaked(address indexed user, uint256 tokenId);
    event NFTUnstaked(address indexed user, uint256 tokenId, uint256 rewardClaimed);

    constructor(IERC20 _rewardToken, IERC721 _nftCollection, uint256 _rewardRatePerSecond) {
        rewardToken = _rewardToken;
        nftCollection = _nftCollection;
        rewardRatePerSecond = _rewardRatePerSecond;
    }

    /**
     * @notice Stake NFTs
     */
    function stake(uint256[] calldata tokenIds) external nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tid = tokenIds[i];
            require(nftCollection.ownerOf(tid) == msg.sender, "Not owner");
            nftCollection.transferFrom(msg.sender, address(this), tid);

            stakes[tid] = Stake(tid, block.timestamp, msg.sender);
            userStakes[msg.sender].push(tid);

            emit NFTStaked(msg.sender, tid);
        }
    }

    /**
     * @notice Unstake NFTs and claim rewards
     */
    function unstake(uint256[] calldata tokenIds) external nonReentrant {
        uint256 totalReward = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            Stake memory s = stakes[tokenIds[i]];
            require(s.owner == msg.sender, "Not staker");

            uint256 reward = (block.timestamp - s.stakedAt) * rewardRatePerSecond;
            totalReward += reward;

            delete stakes[tokenIds[i]];
            nftCollection.transferFrom(address(this), msg.sender, tokenIds[i]);

            emit NFTUnstaked(msg.sender, tokenIds[i], reward);
        }

        if (totalReward > 0) {
            rewardToken.transfer(msg.sender, totalReward);
        }
    }

    /**
     * @notice Update reward rate
     */
    function setRewardRate(uint256 _rewardRatePerSecond) external onlyOwner {
        rewardRatePerSecond = _rewardRatePerSecond;
    }
}
