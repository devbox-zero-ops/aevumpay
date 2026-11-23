import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";

const RPC_URL = process.env.AEVUM_RPC_URL || "https://rpc-test.qday.info";
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!PRIVATE_KEY) {
  console.error("Missing PRIVATE_KEY environment variable.");
  process.exit(1);
}

const art = JSON.parse(fs.readFileSync(path.resolve("artifacts/AevumInvoiceEscrow.json"), "utf8"));
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

const net = await provider.getNetwork();
const bal = await provider.getBalance(wallet.address);
console.log(`Network chainId=${net.chainId} | Deployer=${wallet.address} | Balance=${ethers.formatEther(bal)} tQDAY`);

if (bal === 0n) {
  console.error("Insufficient tQDAY gas balance. Claim test gas from https://faucet.qday.info first.");
  process.exit(2);
}

const factory = new ethers.ContractFactory(art.abi, art.bytecode, wallet);
const contract = await factory.deploy();
const tx = contract.deploymentTransaction();
console.log("Deployment tx:", tx.hash);
await contract.waitForDeployment();
const deployedAddr = await contract.getAddress();
console.log("DEPLOYED AevumInvoiceEscrow:", deployedAddr);
console.log(`Explorer: https://explorer-test.qday.info/address/${deployedAddr}`);
