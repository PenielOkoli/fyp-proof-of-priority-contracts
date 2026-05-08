import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from:", deployer.address);


  const AcademicLedger = await ethers.getContractFactory("contracts/AcademicLedger.sol:AcademicLedger");  const contract = await AcademicLedger.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("AcademicLedger deployed to:", address);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});