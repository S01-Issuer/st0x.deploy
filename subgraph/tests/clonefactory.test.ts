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
import { NewBeaconProxy } from "../generated/CloneFactoryV5/CloneFactoryV5";
import { NewRegistryBeaconProxy } from "../generated/CloneFactoryV6/CloneFactoryV6";
import { NewRegistryBeaconProxy as NewRegistryBeaconProxyV7 } from "../generated/CloneFactoryV7/CloneFactoryV7";
import {
  handleCloneFactoryV5NewBeaconProxy,
  handleCloneFactoryV6NewRegistryBeaconProxy,
  handleCloneFactoryV7NewRegistryBeaconProxy,
} from "../src/clonefactory";
import {
  newBeaconProxyLog,
  newRegistryBeaconProxyLog,
} from "./event-mocks.test";

/**
 * As in `discovery.test.ts`, matchstick's data source registry accumulates
 * across every test in this file and `clearStore` leaves it alone, so the skip
 * tests run first, while the `ReceiptVault` count is still zero, and each match
 * test uses a proxy address no earlier test created.
 */
/** rain-factory-deploy 0.2.1's V5 clone factory. */
const FACTORY_V5 = "0xda3f8841b3f6640ab623050fbba9badc0ccd11b0";
/** rain-factory-deploy 0.2.2's V6 clone factory. */
const FACTORY = "0xb8434a191846f6c3930648aaf264c8e86bf08c62";
/** rain-factory-deploy 0.2.4's V7 clone factory. */
const FACTORY_V7 = "0x087e1d6449a24ff33d30d8d5af260e9b64dad355";
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
  handleCloneFactoryV6NewRegistryBeaconProxy(
    changetype<NewRegistryBeaconProxy>(
      newRegistryBeaconProxyLog(
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

function newProxyV5(
  network: string,
  beacon: string,
  proxy: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  dataSourceMock.setNetwork(network);
  handleCloneFactoryV5NewBeaconProxy(
    changetype<NewBeaconProxy>(
      newBeaconProxyLog(
        Address.fromString(FACTORY_V5),
        Address.fromString(SENDER),
        Address.fromString(beacon),
        Address.fromString(proxy),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function newProxyV7(
  network: string,
  beacon: string,
  proxy: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  dataSourceMock.setNetwork(network);
  handleCloneFactoryV7NewRegistryBeaconProxy(
    changetype<NewRegistryBeaconProxyV7>(
      newRegistryBeaconProxyLog(
        Address.fromString(FACTORY_V7),
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

function assertMatchedBy(
  factory: string,
  proxy: string,
  blockNumber: string,
): void {
  assert.entityCount("Contract", 1);
  assert.fieldEquals("Contract", proxy, "kind", "RECEIPT_VAULT");
  assert.fieldEquals("Contract", proxy, "factory", factory);
  assert.fieldEquals("Contract", proxy, "firstIndexedBlock", blockNumber);
  assert.fieldEquals("Contract", proxy, "ownerFromLog", "false");
  assert.dataSourceExists("ReceiptVault", proxy);
}

function assertMatched(proxy: string, blockNumber: string): void {
  assertMatchedBy(FACTORY, proxy, blockNumber);
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

  test("V7: skips a proxy over another beacon on base", () => {
    newProxyV7(
      "base",
      OTHER_BEACON,
      "0x00000000000000000000000000000000000007a1",
      10,
      0,
    );
    assertSkipped("0x00000000000000000000000000000000000007a1");
  });

  test("V5: skips a proxy over another beacon on base", () => {
    newProxyV5(
      "base",
      OTHER_BEACON,
      "0x00000000000000000000000000000000000001b1",
      10,
      0,
    );
    assertSkipped("0x00000000000000000000000000000000000001b1");
  });

  test("V5: skips on an unknown network even over a known beacon", () => {
    newProxyV5(
      "arbitrum-one",
      BASE_BEACON,
      "0x00000000000000000000000000000000000001b2",
      10,
      0,
    );
    assertSkipped("0x00000000000000000000000000000000000001b2");
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

  test("V5: matches Base's beacon and records the V5 factory", () => {
    newProxyV5(
      "base",
      BASE_BEACON,
      "0x00000000000000000000000000000000000005e1",
      50,
      0,
    );
    assertMatchedBy(
      FACTORY_V5,
      "0x00000000000000000000000000000000000005e1",
      "50",
    );
  });

  test("V5: matches the deployer's beacon on mainnet", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxyV5(
      "mainnet",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000005e2",
      51,
      0,
    );
    assertMatchedBy(
      FACTORY_V5,
      "0x00000000000000000000000000000000000005e2",
      "51",
    );
  });

  test("V7: matches Base's beacon and records the V7 factory", () => {
    newProxyV7(
      "base",
      BASE_BEACON,
      "0x00000000000000000000000000000000000007e1",
      60,
      0,
    );
    assertMatchedBy(
      FACTORY_V7,
      "0x00000000000000000000000000000000000007e1",
      "60",
    );
  });

  test("V7: matches the deployer's beacon on robinhood", () => {
    mockDeployerBeacon(BEACON_0_1_1);
    newProxyV7(
      "robinhood",
      BEACON_0_1_1,
      "0x00000000000000000000000000000000000007e2",
      61,
      0,
    );
    assertMatchedBy(
      FACTORY_V7,
      "0x00000000000000000000000000000000000007e2",
      "61",
    );
  });

  test("a proxy one factory indexed is not taken over by another", () => {
    let proxy = "0x00000000000000000000000000000000000005e3";
    newProxyV5("base", BASE_BEACON, proxy, 52, 0);
    newProxy("base", BASE_BEACON, proxy, 53, 1);
    assertMatchedBy(FACTORY_V5, proxy, "52");
  });

  test("a second log for an indexed proxy writes nothing new", () => {
    let proxy = "0x00000000000000000000000000000000000004d1";
    newProxy("base", BASE_BEACON, proxy, 40, 0);
    newProxy("base", BASE_BEACON, proxy, 41, 1);
    assertMatched(proxy, "40");
  });
});
