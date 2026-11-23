import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const RPC_URL = "https://rpc-test.qday.info";
const EXPECTED_CHAIN_ID = 44005;
const TUSD8_ADDR = "0x456569838f1d43009A91ebA4263147Afd7233483";

async function rpc(method, params = []) {
  const res = await fetch(RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  assert.equal(res.status, 200, "Aevum RPC should return HTTP 200");
  const data = await res.json();
  assert.ok(!data.error, `RPC error: ${JSON.stringify(data.error)}`);
  return data.result;
}

test("Compiled AevumInvoiceEscrow artifact has valid ABI and bytecode", () => {
  const artPath = path.resolve("artifacts/AevumInvoiceEscrow.json");
  assert.ok(fs.existsSync(artPath), "Artifact JSON must exist");
  const art = JSON.parse(fs.readFileSync(artPath, "utf8"));
  assert.equal(art.contractName, "AevumInvoiceEscrow");
  assert.equal(art.chainId, EXPECTED_CHAIN_ID);
  assert.equal(art.tUSD8.toLowerCase(), TUSD8_ADDR.toLowerCase());
  assert.ok(art.bytecode.startsWith("0x") && art.bytecode.length > 2000, "Bytecode should be non-empty hex");

  const fnNames = new Set(art.abi.filter((x) => x.type === "function").map((x) => x.name));
  for (const required of ["createInvoice", "payInvoice", "releaseEscrow", "refundEscrow", "cancelInvoice", "invoices"]) {
    assert.ok(fnNames.has(required), `ABI must expose function ${required}`);
  }
});

test("QDay Aevum Testnet RPC responds with Chain ID 44005 and live blocks", async () => {
  const chainHex = await rpc("eth_chainId");
  assert.equal(parseInt(chainHex, 16), EXPECTED_CHAIN_ID);
  const blockHex = await rpc("eth_blockNumber");
  assert.ok(parseInt(blockHex, 16) > 0, "Aevum testnet should have positive block height");
});

test("Official tUSD8 ERC-20 contract on Aevum Testnet exposes 6 decimals", async () => {
  // decimals() selector = 0x313ce567
  const decHex = await rpc("eth_call", [{ to: TUSD8_ADDR, data: "0x313ce567" }, "latest"]);
  assert.equal(parseInt(decHex, 16), 6, "tUSD8 must return 6 decimals");
});
