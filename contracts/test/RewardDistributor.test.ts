import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";

describe("RewardDistributorUpgradeable", function () {
  let RewardDistributor: any;
  let distributor: Contract;
  let owner: any, addr1: any, addr2: any;

  before(async () => {
    [owner, addr1, addr2] = await ethers.getSigners();

    RewardDistributor = await ethers.getContractFactory("RewardDistributorUpgradeable");

    distributor = await upgrades.deployProxy(
      RewardDistributor,
      [owner.address, ethers.utils.parseEther("1000000")], // owner + initial supply or cap
      { initializer: "initialize" }
    );
    await distributor.deployed();
  });

  it("Should deploy upgradeable contract correctly", async function () {
    expect(await distributor.owner()).to.equal(owner.address);
  });

  it("Should set and get distribution rate", async function () {
    await distributor.setDistributionRate(ethers.utils.parseEther("10"));
    const rate = await distributor.distributionRate();
    expect(rate).to.equal(ethers.utils.parseEther("10"));
  });

  it("Should distribute rewards to a single user", async function () {
    const amount = ethers.utils.parseEther("50");

    await expect(distributor.distributeReward(addr1.address, amount))
      .to.emit(distributor, "RewardDistributed")
      .withArgs(addr1.address, amount);

    const balance = await distributor.rewards(addr1.address);
    expect(balance).to.equal(amount);
  });

  it("Should distribute to multiple users in batch", async function () {
    const addresses = [addr1.address, addr2.address];
    const amounts = [
      ethers.utils.parseEther("30"),
      ethers.utils.parseEther("40"),
    ];

    await expect(distributor.batchDistribute(addresses, amounts))
      .to.emit(distributor, "RewardBatchDistributed");

    const balance1 = await distributor.rewards(addr1.address);
    const balance2 = await distributor.rewards(addr2.address);

    expect(balance1).to.equal(ethers.utils.parseEther("80")); // 50 + 30
    expect(balance2).to.equal(ethers.utils.parseEther("40"));
  });

  it("Should prevent non-owner from distributing", async function () {
    const amount = ethers.utils.parseEther("10");
    await expect(
      distributor.connect(addr1).distributeReward(addr2.address, amount)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });
});
