import {
  afterEach,
  assert,
  clearStore,
  createMockedFunction,
  describe,
  test,
} from "matchstick-as";
import { Address, ethereum } from "@graphprotocol/graph-ts";
import { Deployment } from "../generated/ReceiptVaultDeployer/OffchainAssetReceiptVaultBeaconSetDeployer";
import { Deployment as OrchestratorDeployment } from "../generated/OrchestratorDeployer/ST0xOrchestratorBeaconSetDeployer";
import { handleReceiptVaultDeployment } from "../src/receiptvaultdeployer";
import { handleOrchestratorDeployment } from "../src/orchestratordeployer";
import {
  orchestratorDeploymentLog,
  receiptVaultDeploymentLog,
} from "./event-mocks.test";

const RECEIPT_VAULT_DEPLOYER = "0x2191981ca2477b745870cc307cbeb4cb2967ace3";
const ORCHESTRATOR_DEPLOYER = "0x945d0faf6f268e805246907507ef1044e70e75d7";
const VAULT = "0x00000000000000000000000000000000000000da";
const OTHER_VAULT = "0x00000000000000000000000000000000000000db";
const RECEIPT = "0x00000000000000000000000000000000000000dc";
const ORCHESTRATOR = "0x00000000000000000000000000000000000000c0";
const VAULT_BEACON = "0x0000000000000000000000000000000000000f01";
const RECEIPT_BEACON = "0x0000000000000000000000000000000000000f02";
const BEACON_OWNER = "0x00000000000000000000000000000000000000a1";
const VAULT_IMPLEMENTATION = "0x0000000000000000000000000000000000000e01";
const RECEIPT_IMPLEMENTATION = "0x0000000000000000000000000000000000000e02";
const SENDER = "0x00000000000000000000000000000000000000ca";
const OWNER = "0x00000000000000000000000000000000000000a2";

/**
 * Mock the beacon getters in the camelCase spelling the current deployer
 * generation uses, leaving the screaming-snake pair reverting as it does on a
 * chain running that generation.
 */
function mockCamelCaseGetters(): void {
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "iOffchainAssetReceiptVaultBeacon",
    "iOffchainAssetReceiptVaultBeacon():(address)",
  ).returns([ethereum.Value.fromAddress(Address.fromString(VAULT_BEACON))]);
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "iReceiptBeacon",
    "iReceiptBeacon():(address)",
  ).returns([ethereum.Value.fromAddress(Address.fromString(RECEIPT_BEACON))]);
}

/**
 * Mock the getters in the pre-rename spelling only, which is what the
 * Base-generation deployer answers.
 */
function mockScreamingSnakeGetters(): void {
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "iOffchainAssetReceiptVaultBeacon",
    "iOffchainAssetReceiptVaultBeacon():(address)",
  ).reverts();
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "iReceiptBeacon",
    "iReceiptBeacon():(address)",
  ).reverts();
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON",
    "I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON():(address)",
  ).returns([ethereum.Value.fromAddress(Address.fromString(VAULT_BEACON))]);
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "I_RECEIPT_BEACON",
    "I_RECEIPT_BEACON():(address)",
  ).returns([ethereum.Value.fromAddress(Address.fromString(RECEIPT_BEACON))]);
}

function mockNoGetters(): void {
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "iOffchainAssetReceiptVaultBeacon",
    "iOffchainAssetReceiptVaultBeacon():(address)",
  ).reverts();
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "iReceiptBeacon",
    "iReceiptBeacon():(address)",
  ).reverts();
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON",
    "I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON():(address)",
  ).reverts();
  createMockedFunction(
    Address.fromString(RECEIPT_VAULT_DEPLOYER),
    "I_RECEIPT_BEACON",
    "I_RECEIPT_BEACON():(address)",
  ).reverts();
}

function mockBeaconState(
  beacon: string,
  owner: string,
  implementation: string,
): void {
  createMockedFunction(
    Address.fromString(beacon),
    "owner",
    "owner():(address)",
  ).returns([ethereum.Value.fromAddress(Address.fromString(owner))]);
  createMockedFunction(
    Address.fromString(beacon),
    "implementation",
    "implementation():(address)",
  ).returns([
    ethereum.Value.fromAddress(Address.fromString(implementation)),
  ]);
}

function mockBothBeacons(): void {
  mockBeaconState(VAULT_BEACON, BEACON_OWNER, VAULT_IMPLEMENTATION);
  mockBeaconState(RECEIPT_BEACON, BEACON_OWNER, RECEIPT_IMPLEMENTATION);
}

function deployVault(vault: string, blockNumber: i32, logIndex: i32): void {
  handleReceiptVaultDeployment(
    changetype<Deployment>(
      receiptVaultDeploymentLog(
        Address.fromString(RECEIPT_VAULT_DEPLOYER),
        Address.fromString(SENDER),
        Address.fromString(vault),
        Address.fromString(RECEIPT),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

describe("Receipt vault discovery", () => {
  afterEach(clearStore);

  test("a deployment creates the vault data source and both beacons", () => {
    mockCamelCaseGetters();
    mockBothBeacons();

    deployVault(VAULT, 1000, 5);

    assert.dataSourceCount("ReceiptVault", 1);
    assert.dataSourceExists("ReceiptVault", VAULT);
    assert.dataSourceCount("VaultBeacon", 2);
    assert.dataSourceExists("VaultBeacon", VAULT_BEACON);
    assert.dataSourceExists("VaultBeacon", RECEIPT_BEACON);

    assert.entityCount("Contract", 3);
    assert.fieldEquals("Contract", VAULT, "kind", "RECEIPT_VAULT");
    assert.fieldEquals("Contract", VAULT, "firstIndexedBlock", "1000");
    // The vault's own first `OwnershipTransferred` is replayed into the new
    // template, so nothing is read or claimed for it here.
    assert.fieldEquals("Contract", VAULT, "ownerFromLog", "false");

    assert.fieldEquals("Contract", VAULT_BEACON, "kind", "BEACON");
    assert.fieldEquals("Contract", VAULT_BEACON, "owner", BEACON_OWNER);
    assert.fieldEquals("Contract", VAULT_BEACON, "ownerAsOfBlock", "1000");
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementation",
      VAULT_IMPLEMENTATION,
    );
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementationAsOfBlock",
      "1000",
    );
    // Both values came from a call at the discovery block, not from a log:
    // the beacons are built in the deployer's constructor, in a block this
    // subgraph never indexes.
    assert.fieldEquals("Contract", VAULT_BEACON, "ownerFromLog", "false");
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementationFromLog",
      "false",
    );
    assert.fieldEquals(
      "Contract",
      RECEIPT_BEACON,
      "implementation",
      RECEIPT_IMPLEMENTATION,
    );

    // Discovery establishes current state only. Inventing history rows for it
    // would put entries in `ownershipTransfers` / `upgrades` with no log.
    assert.entityCount("OwnershipTransfer", 0);
    assert.entityCount("BeaconUpgrade", 0);
  });

  test("the pre-rename getter spelling is the fallback", () => {
    mockScreamingSnakeGetters();
    mockBothBeacons();

    deployVault(VAULT, 1000, 5);

    assert.dataSourceCount("VaultBeacon", 2);
    assert.fieldEquals("Contract", VAULT_BEACON, "owner", BEACON_OWNER);
    assert.fieldEquals(
      "Contract",
      RECEIPT_BEACON,
      "implementation",
      RECEIPT_IMPLEMENTATION,
    );
  });

  test("a second deployment does not re-create the beacon data sources", () => {
    mockCamelCaseGetters();
    mockBothBeacons();

    deployVault(VAULT, 1000, 5);
    deployVault(OTHER_VAULT, 2000, 1);

    assert.dataSourceCount("ReceiptVault", 2);
    assert.dataSourceCount("VaultBeacon", 2);
    assert.entityCount("Contract", 4);
    // The beacons keep the block they were first seen in.
    assert.fieldEquals("Contract", VAULT_BEACON, "firstIndexedBlock", "1000");
    assert.fieldEquals("Contract", OTHER_VAULT, "firstIndexedBlock", "2000");
  });

  test("a replayed deployment creates one vault data source", () => {
    mockCamelCaseGetters();
    mockBothBeacons();

    deployVault(VAULT, 1000, 5);
    deployVault(VAULT, 1000, 5);

    assert.dataSourceCount("ReceiptVault", 1);
    assert.dataSourceCount("VaultBeacon", 2);
    assert.entityCount("Contract", 3);
  });

  test("the vault is still indexed when no beacon getter answers", () => {
    mockNoGetters();

    deployVault(VAULT, 1000, 5);

    assert.dataSourceCount("ReceiptVault", 1);
    assert.dataSourceCount("VaultBeacon", 0);
    assert.entityCount("Contract", 1);
    assert.fieldEquals("Contract", VAULT, "kind", "RECEIPT_VAULT");
  });

  test("a beacon whose owner call reverts is indexed without one", () => {
    mockCamelCaseGetters();
    createMockedFunction(
      Address.fromString(VAULT_BEACON),
      "owner",
      "owner():(address)",
    ).reverts();
    createMockedFunction(
      Address.fromString(VAULT_BEACON),
      "implementation",
      "implementation():(address)",
    ).returns([
      ethereum.Value.fromAddress(Address.fromString(VAULT_IMPLEMENTATION)),
    ]);
    mockBeaconState(RECEIPT_BEACON, BEACON_OWNER, RECEIPT_IMPLEMENTATION);

    deployVault(VAULT, 1000, 5);

    assert.dataSourceCount("VaultBeacon", 2);
    assert.fieldEquals("Contract", VAULT_BEACON, "kind", "BEACON");
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementation",
      VAULT_IMPLEMENTATION,
    );
    assert.fieldEquals("Contract", VAULT_BEACON, "ownerFromLog", "false");
  });
});

describe("Orchestrator discovery", () => {
  afterEach(clearStore);

  test("a deployment creates the data source and seeds no roles", () => {
    handleOrchestratorDeployment(
      changetype<OrchestratorDeployment>(
        orchestratorDeploymentLog(
          Address.fromString(ORCHESTRATOR_DEPLOYER),
          Address.fromString(SENDER),
          Address.fromString(ORCHESTRATOR),
          Address.fromString(OWNER),
          3000,
          0,
        ),
      ),
    );

    assert.dataSourceCount("Orchestrator", 1);
    assert.dataSourceExists("Orchestrator", ORCHESTRATOR);
    assert.entityCount("Contract", 1);
    assert.fieldEquals("Contract", ORCHESTRATOR, "kind", "ORCHESTRATOR");
    assert.fieldEquals("Contract", ORCHESTRATOR, "firstIndexedBlock", "3000");

    // The `owner` param is NOT seeded as a `DEFAULT_ADMIN_ROLE` holder: the
    // orchestrator's own `RoleGranted` is replayed into the new template, and
    // writing it here as well would invent a grant with no log behind it.
    assert.entityCount("Role", 0);
    assert.entityCount("RoleHolder", 0);
    assert.entityCount("RoleGrant", 0);
  });

  test("a replayed deployment creates one data source", () => {
    handleOrchestratorDeployment(
      changetype<OrchestratorDeployment>(
        orchestratorDeploymentLog(
          Address.fromString(ORCHESTRATOR_DEPLOYER),
          Address.fromString(SENDER),
          Address.fromString(ORCHESTRATOR),
          Address.fromString(OWNER),
          3000,
          0,
        ),
      ),
    );
    handleOrchestratorDeployment(
      changetype<OrchestratorDeployment>(
        orchestratorDeploymentLog(
          Address.fromString(ORCHESTRATOR_DEPLOYER),
          Address.fromString(SENDER),
          Address.fromString(ORCHESTRATOR),
          Address.fromString(OWNER),
          3000,
          0,
        ),
      ),
    );

    assert.dataSourceCount("Orchestrator", 1);
    assert.entityCount("Contract", 1);
  });
});
