async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with", deployer.address);

  const Atlas = await ethers.getContractFactory("AtlasToken");
  const atlas = await Atlas.deploy("Atlas Token", "ATLAS");
  await atlas.deployed();
  console.log("AtlasToken:", atlas.address);

  const Bridge = await ethers.getContractFactory("Bridge");
  const bridge = await Bridge.deploy(deployer.address); // admin
  await bridge.deployed();
  console.log("Bridge:", bridge.address);

  // grant roles: bridge needs MINTER_ROLE on AtlasToken
  const MINTER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("MINTER_ROLE"));
  await atlas.grantRole(MINTER_ROLE, bridge.address);
  console.log("Granted MINTER_ROLE to Bridge");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
