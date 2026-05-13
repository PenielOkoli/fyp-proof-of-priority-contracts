import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AcademicLedger v4 from:", deployer.address);

  const AcademicLedger = await ethers.getContractFactory("contracts/AcademicLedger.sol:AcademicLedger");
  const contract       = await AcademicLedger.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  const receipt = await contract.deploymentTransaction()?.wait();

  console.log("Deployed to:      ", address);
  console.log("Deployment block: ", receipt?.blockNumber);
  console.log("\n=== Copy these to your frontend .env.local ===");
  console.log(`NEXT_PUBLIC_CONTRACT_ADDRESS=${address}`);
  console.log(`NEXT_PUBLIC_DEPLOY_BLOCK=${receipt?.blockNumber}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});