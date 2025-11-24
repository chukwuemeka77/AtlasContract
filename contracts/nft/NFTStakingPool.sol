// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./NFTCollection.sol";

contract NFTStakingPool is Ownable {
    IERC20 public rewardToken; // rewards in Atlas
    NFTCollection public nftCollection;

    struct StakeInfo {
        uint256[] tokenIds;
        uint256 rewardDebt;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public accRewardPerNFT; // accumulated rewards per NFT, scaled by 1e12

    event NFTStaked(address indexed user, uint256[] tokenIds);
    event NFTUnstaked(address indexed user, uint256[] tokenIds);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(address _rewardToken, address _nftCollection) {
        rewardToken = IERC20(_rewardToken);
        nftCollection = NFTCollection(_nftCollection);
    }

    // ---------------------------
    // Stake NFTs
    // ---------------------------
    function stake(uint256[] calldata tokenIds) external {
        require(tokenIds.length > 0, "No NFTs");

        _updateRewards(msg.sender);

        for (uint i = 0; i < tokenIds.length; i++) {
            nftCollection.transferFrom(msg.sender, address(this), tokenIds[i]);
            stakes[msg.sender].tokenIds.push(tokenIds[i]);
        }

        emit NFTStaked(msg.sender, tokenIds);
    }

    // ---------------------------
    // Unstake NFTs
    // ---------------------------
    function unstake(uint256[] calldata tokenIds) external {
        _updateRewards(msg.sender);

        StakeInfo storage s = stakes[msg.sender];
        require(tokenIds.length <= s.tokenIds.length, "Too many NFTs");

        for (uint i = 0; i < tokenIds.length; i++) {
            bool removed = false;
            for (uint j = 0; j < s.tokenIds.length; j++) {
                if (s.tokenIds[j] == tokenIds[i]) {
                    s.tokenIds[j] = s.tokenIds[s.tokenIds.length - 1];
                    s.tokenIds.pop();
                    removed = true;
                    break;
                }
            }
            require(removed, "NFT not staked");
            nftCollection.transferFrom(address(this), msg.sender, tokenIds[i]);
        }

        emit NFTUnstaked(msg.sender, tokenIds);
    }

    // ---------------------------
    // Claim rewards
    // ---------------------------
    function claim() external {
        _updateRewards(msg.sender);
    }

    function _updateRewards(address user) internal {
        StakeInfo storage s = stakes[user];
        uint256 pending = (s.tokenIds.length * accRewardPerNFT) - s.rewardDebt;
        if (pending > 0) {
            rewardToken.transfer(user, pending);
            emit RewardClaimed(user, pending);
        }
        s.rewardDebt = s.tokenIds.length * accRewardPerNFT;
    }

    // ---------------------------
    // Add rewards (from reward distributor)
    // ---------------------------
    function notifyRewardAmount(uint256 amount) external onlyOwner {
        uint256 totalStaked = totalStakedNFTs();
        require(totalStaked > 0, "No NFTs staked");
        accRewardPerNFT += (amount * 1e12) / totalStaked;
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    function totalStakedNFTs() public view returns (uint256) {
        uint256 total = 0;
        // iterate through users would require off-chain indexing
        // optionally track total staked separately
        return total;
    }
}
