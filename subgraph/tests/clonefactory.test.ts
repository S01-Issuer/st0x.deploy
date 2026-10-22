import {
  afterEach,
  assert,
  clearStore,
  createMockedFunction,
  dataSourceMock,
  describe,
  test,
} from "matchstick-as";
import { Address, ethereum } from "@graphprotocol/graph-ts";
import { NewBeaconProxy } from "../generated/CloneFactory/CloneFactory";
import { handleCloneFactoryNewBeaconProxy } from "../src/clonefactory";
import { newBeaconProxyLog } from "./event-mocks.test";

/**
 * As in `discovery.test.ts`, matchstick's data source registry accumulates
 * across every test in this file and `clearStore` leaves it alone, so the skip
 * tests run first, while the `ReceiptVault` count is still zero, and each match
 * test uses a proxy address no earlier test created.
 */
const FACTORY = "0xda3f8841b3f6640ab623050fbba9badc0ccd11b0";
/** st0x `LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1`. */
const BASE_BEACON = "0xea084c8f4331cdf3328e772781b59f8a24f28f1a";
/** st0x `LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1`. */
const DEPLOYER_0_1_1 = "0xd64246e6b25f745f005e6233e050c9b879e660dc";
/** What the mocked 0.1.1 deployer getter answers. */
const BEACON_0_1_1 = "0x0000000000000000000000000000000000000b11";
const OTHER_BEACON = "0x0000000000000000000000000000000000000bad";
const SENDER = "0x00000000000000000000000000000000000000ca";

function mockDeployerBeacon(beacon: string): void {
  createMockedFunction(
    Address.fromString(DEPLOYER_0_1_1),
    "iOffchainAssetReceiptVaultBeacon",
    "iOffchainAssetReceiptVaultBeacon():(address)",
  ).returns([ethereum.Value.fromAddress(Address.fromString(beacon))]);
}

function mockDeployerReverts(): void {
  createMockedFunction(
    Address.fromString(DEPLOYER_0_1_1),
    "iOffchainAssetReceiptVaultBeacon",
    "iOffchainAssetReceiptVaultBeacon():(address)",
  ).reverts();
}

function newProxy(
  network: string,
  beacon: string,
  proxy: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  dataSourceMock.setNetwork(network);
  handleCloneFactoryNewBeaconProxy(
    changetype<NewBeaconProxy>(
      newBeaconProxyLog(
        Address.fromString(FACTORY),
        Address.fromString(SENDER),
        Address.fromString(beacon),
        Address.fromString(proxy),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function assertSkipped(proxy: string): void {
  assert.notInStore("Contract", proxy);
  assert.entityCount("Contract", 0);
  assert.dataSourceCount("ReceiptVault", 0);
}

function assertMatched(proxy: string, blockNumber: string): void {
  assert.entityCount("Contract", 1);
  assert.fieldEquals("Contract", proxy, "kind", "RECEIPT_VAULT");
  assert.fieldEquals("Contract", proxy, "firstIndexedBlock", blockNumber);
  assert.fieldEquals("Contract", proxy, "ownerFromLog", "false");
  assert.dataSourceExists("ReceiptVault", proxy);
}

describe("Clone factory vault discovery", () => {
  afterEach(() => {
    clearStore();
    dataSourceMock.resetValues();
  });

  test("skips a proxy over another beacon on base", () => {
    newProxy(
      "base",
      OTHER_BEACON,
      "0x00000000000000000000000000000000000001a1",
      10,
      0,
    );
    assertSkipped("0x00000000000000000000000000000000000001a1");
  });

  test("skips a proxy over another beacon on a 0.1.1 chain", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "mainnet",
      OTHER_BEACON,
      "0x00000000000000000000000000000000000001a2",
      10,
      0,
    );
    assertSkipped("0x00000000000000000000000000000000000001a2");
  });

  test("skips on an unknown network even over a known beacon", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "arbitrum-one",
      BASE_BEACON,
      "0x00000000000000000000000000000000000001a3",
      10,
      0,
    );
    newProxy(
      "arbitrum-one",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000001a4",
      10,
      1,
    );
    assertSkipped("0x00000000000000000000000000000000000001a3");
    assertSkipped("0x00000000000000000000000000000000000001a4");
  });

  test("skips on a 0.1.1 chain when the deployer getter reverts", () => {
    mockDeployerReverts();
    newProxy(
      "mainnet",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000001a5",
      10,
      0,
    );
    newProxy(
      "mainnet",
      BASE_BEACON,
      "0x00000000000000000000000000000000000001a6",
      10,
      1,
    );
    assertSkipped("0x00000000000000000000000000000000000001a5");
    assertSkipped("0x00000000000000000000000000000000000001a6");
  });

  test("skips Base's beacon on a 0.1.1 chain", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "mainnet",
      BASE_BEACON,
      "0x00000000000000000000000000000000000001a7",
      10,
      0,
    );
    assertSkipped("0x00000000000000000000000000000000000001a7");
  });

  test("on base, matches Base's pinned beacon without reading the deployer", () => {
    // Base answers from its constant: the deployer getter is never consulted,
    // so neither a reverting getter nor one naming another beacon moves it.
    mockDeployerReverts();
    newProxy(
      "base",
      BASE_BEACON,
      "0x00000000000000000000000000000000000002b1",
      20,
      0,
    );
    assertMatched("0x00000000000000000000000000000000000002b1", "20");
  });

  test("on base, skips the beacon the 0.1.1 deployer names", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "base",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000002b2",
      20,
      0,
    );
    assert.notInStore("Contract", "0x00000000000000000000000000000000000002b2");
    assert.entityCount("Contract", 0);
  });

  test("matches the deployer's beacon on mainnet", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "mainnet",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000003c1",
      30,
      0,
    );
    assertMatched("0x00000000000000000000000000000000000003c1", "30");
  });

  test("matches the deployer's beacon on hyperevm", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "hyperevm",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000003c2",
      31,
      0,
    );
    assertMatched("0x00000000000000000000000000000000000003c2", "31");
  });

  test("matches the deployer's beacon on robinhood", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "robinhood",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000003c3",
      32,
      0,
    );
    assertMatched("0x00000000000000000000000000000000000003c3", "32");
  });

  test("matches the deployer's beacon on bsc", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxy(
      "bsc",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000003c4",
      33,
      0,
    );
    assertMatched("0x00000000000000000000000000000000000003c4", "33");
  });

  test("a second log for an indexed proxy writes nothing new", () => {
    let proxy = "0x00000000000000000000000000000000000004d1";
    newProxy("base", BASE_BEACON, proxy, 40, 0);
    newProxy("base", BASE_BEACON, proxy, 41, 1);
    assertMatched(proxy, "40");
  });
});
