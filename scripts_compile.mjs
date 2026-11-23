import fs from "node:fs";
import path from "node:path";
import solc from "solc";

const src = fs.readFileSync(path.resolve("contracts/AevumInvoiceEscrow.sol"), "utf8");
const input = {
  language: "Solidity",
  sources: { "AevumInvoiceEscrow.sol": { content: src } },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } }
  }
};
const out = JSON.parse(solc.compile(JSON.stringify(input)));
if (out.errors) {
  for (const e of out.errors) console.log(e.severity.toUpperCase(), e.formattedMessage);
  if (out.errors.some(e => e.severity === "error")) process.exit(1);
}
const c = out.contracts["AevumInvoiceEscrow.sol"]["AevumInvoiceEscrow"];
fs.mkdirSync("artifacts", { recursive: true });
fs.writeFileSync("artifacts/AevumInvoiceEscrow.json", JSON.stringify({
  contractName: "AevumInvoiceEscrow",
  compiler: "solc 0.8.20 (optimizer 200)",
  chainId: 44005,
  network: "QDay Aevum Testnet",
  tUSD8: "0x456569838f1d43009A91ebA4263147Afd7233483",
  abi: c.abi,
  bytecode: "0x" + c.evm.bytecode.object
}, null, 2));
console.log("COMPILED OK | ABI items:", c.abi.length, "| Bytecode bytes:", c.evm.bytecode.object.length / 2);
