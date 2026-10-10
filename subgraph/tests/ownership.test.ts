import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address } from "@graphprotocol/graph-ts";
import {
  OwnershipTransferred,
  Upgraded,
} from "../generated/WrappedTokenVaultBeacon/UpgradeableBeacon";
import { OwnershipTransferred as VaultOwnershipTransferred } from "../generated/templates/ReceiptVault/Ownable";
import {
  OwnershipTransferred as VaultBeaconOwnershipTransferred,
  Upgraded as VaultBeaconUpgraded,
} from "../generated/templates/VaultBeacon/UpgradeableBeacon";
import {
  OwnershipTransferred as OrchestratorBeaconOwnershipTransferred,
  Upgraded as OrchestratorBeaconUpgraded,
} from "../generated/OrchestratorBeacon/UpgradeableBeacon";
import {
  handleWrappedTokenVaultBeaconOwnershipTransferred,
  handleWrappedTokenVaultBeaconUpgraded,
} from "../src/wrappedtokenvaultbeacon";
import {
  handleVaultBeaconOwnershipTransferred,
  handleVaultBeaconUpgraded,
} from "../src/vaultbeacon";
import {
  handleOrchestratorBeaconOwnershipTransferred,
  handleOrchestratorBeaconUpgraded,
} from "../src/orchestratorbeacon";
import { handleReceiptVaultOwnershipTransferred } from "../src/receiptvault";
import {
  TX_FROM,
  TX_HASH,
  ownershipTransferredLog,
  upgradedLog,
} from "./event-mocks.test";

const BEACON = "0x4c2d2d3bf1232bf0d3fb7123007a9b8444637bc8";
const VAULT = "0x00000000000000000000000000000000000000da";
const ZERO = "0x0000000000000000000000000000000000000000";
const ALICE = "0x00000000000000000000000000000000000000a1";
const BOB = "0x00000000000000000000000000000000000000b0";
const IMPLEMENTATION = "0x00000000000000000000000000000000000000e1";
const VAULT_BEACON = "0x00000000000000000000000000000000000000b1";
const ORCHESTRATOR_BEACON = "0x00000000000000000000000000000000000000b2";

function transferBeaconOwnership(
  previousOwner: string,
  newOwner: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleWrappedTokenVaultBeaconOwnershipTransferred(
    changetype<OwnershipTransferred>(
      ownershipTransferredLog(
        Address.fromString(BEACON),
        Address.fromString(previousOwner),
        Address.fromString(newOwner),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function rowKey(logIndex: i32): string {
  return TX_HASH.concatI32(logIndex).toHexString();
}

describe("Ownership", () => {
  afterEach(clearStore);

  test("a transfer sets the owner from the log", () => {
    transferBeaconOwnership(ZERO, ALICE, 50, 0);

    assert.entityCount("Contract", 1);
    assert.entityCount("OwnershipTransfer", 1);
    assert.fieldEquals("Contract", BEACON, "kind", "BEACON");
    assert.fieldEquals("Contract", BEACON, "firstIndexedBlock", "50");
    assert.fieldEquals("Contract", BEACON, "owner", ALICE);
    assert.fieldEquals("Contract", BEACON, "ownerAsOfBlock", "50");
    assert.fieldEquals("Contract", BEACON, "ownerFromLog", "true");

    let row = rowKey(0);
    assert.fieldEquals("OwnershipTransfer", row, "contract", BEACON);
    assert.fieldEquals("OwnershipTransfer", row, "previousOwner", ZERO);
    assert.fieldEquals("OwnershipTransfer", row, "newOwner", ALICE);
    assert.fieldEquals("OwnershipTransfer", row, "blockNumber", "50");
    assert.fieldEquals("OwnershipTransfer", row, "blockTimestamp", "600");
    assert.fieldEquals(
      "OwnershipTransfer",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "OwnershipTransfer",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("OwnershipTransfer", row, "logIndex", "0");
  });

  test("a second transfer moves the owner and keeps both rows", () => {
    transferBeaconOwnership(ZERO, ALICE, 50, 0);
    transferBeaconOwnership(ALICE, BOB, 60, 1);

    assert.entityCount("OwnershipTransfer", 2);
    assert.fieldEquals("Contract", BEACON, "owner", BOB);
    assert.fieldEquals("Contract", BEACON, "ownerAsOfBlock", "60");
    // The lower bound of the indexed history never moves forward.
    assert.fieldEquals("Contract", BEACON, "firstIndexedBlock", "50");
  });

  test("a renounce records the zero address as the owner", () => {
    transferBeaconOwnership(ZERO, ALICE, 50, 0);
    transferBeaconOwnership(ALICE, ZERO, 70, 0);

    assert.fieldEquals("Contract", BEACON, "owner", ZERO);
    assert.fieldEquals("Contract", BEACON, "ownerAsOfBlock", "70");
    assert.fieldEquals("Contract", BEACON, "ownerFromLog", "true");
  });

  test("a receipt vault transfer is recorded against the vault kind", () => {
    handleReceiptVaultOwnershipTransferred(
      changetype<VaultOwnershipTransferred>(
        ownershipTransferredLog(
          Address.fromString(VAULT),
          Address.fromString(ZERO),
          Address.fromString(ALICE),
          80,
          2,
        ),
      ),
    );

    assert.fieldEquals("Contract", VAULT, "kind", "RECEIPT_VAULT");
    assert.fieldEquals("Contract", VAULT, "owner", ALICE);
    assert.fieldEquals("Contract", VAULT, "ownerFromLog", "true");
  });
});

describe("Beacon upgrades", () => {
  afterEach(clearStore);

  test("an upgrade sets the implementation from the log", () => {
    handleWrappedTokenVaultBeaconUpgraded(
      changetype<Upgraded>(
        upgradedLog(
          Address.fromString(BEACON),
          Address.fromString(IMPLEMENTATION),
          70,
          1,
        ),
      ),
    );

    assert.entityCount("Contract", 1);
    assert.entityCount("BeaconUpgrade", 1);
    assert.fieldEquals("Contract", BEACON, "implementation", IMPLEMENTATION);
    assert.fieldEquals("Contract", BEACON, "implementationAsOfBlock", "70");
    assert.fieldEquals("Contract", BEACON, "implementationFromLog", "true");
    // An upgrade says nothing about ownership and must not claim to.
    assert.fieldEquals("Contract", BEACON, "ownerFromLog", "false");

    let row = rowKey(1);
    assert.fieldEquals("BeaconUpgrade", row, "contract", BEACON);
    assert.fieldEquals("BeaconUpgrade", row, "implementation", IMPLEMENTATION);
    assert.fieldEquals("BeaconUpgrade", row, "blockNumber", "70");
    assert.fieldEquals("BeaconUpgrade", row, "blockTimestamp", "840");
    assert.fieldEquals("BeaconUpgrade", row, "logIndex", "1");
  });

  test("an upgrade and a transfer on one beacon share a Contract row", () => {
    transferBeaconOwnership(ZERO, ALICE, 50, 0);
    handleWrappedTokenVaultBeaconUpgraded(
      changetype<Upgraded>(
        upgradedLog(
          Address.fromString(BEACON),
          Address.fromString(IMPLEMENTATION),
          70,
          1,
        ),
      ),
    );

    assert.entityCount("Contract", 1);
    assert.fieldEquals("Contract", BEACON, "owner", ALICE);
    assert.fieldEquals("Contract", BEACON, "ownerFromLog", "true");
    assert.fieldEquals("Contract", BEACON, "implementation", IMPLEMENTATION);
    assert.fieldEquals("Contract", BEACON, "implementationFromLog", "true");
    assert.fieldEquals("Contract", BEACON, "firstIndexedBlock", "50");
  });
});

describe("Vault and orchestrator beacons", () => {
  afterEach(clearStore);

  test("a vault beacon transfer and upgrade share one BEACON row", () => {
    handleVaultBeaconOwnershipTransferred(
      changetype<VaultBeaconOwnershipTransferred>(
        ownershipTransferredLog(
          Address.fromString(VAULT_BEACON),
          Address.fromString(ZERO),
          Address.fromString(ALICE),
          50,
          0,
        ),
      ),
    );

    assert.fieldEquals("Contract", VAULT_BEACON, "kind", "BEACON");
    assert.fieldEquals("Contract", VAULT_BEACON, "owner", ALICE);
    assert.fieldEquals("Contract", VAULT_BEACON, "ownerFromLog", "true");
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementationFromLog",
      "false",
    );

    handleVaultBeaconUpgraded(
      changetype<VaultBeaconUpgraded>(
        upgradedLog(
          Address.fromString(VAULT_BEACON),
          Address.fromString(IMPLEMENTATION),
          70,
          1,
        ),
      ),
    );

    assert.entityCount("Contract", 1);
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementation",
      IMPLEMENTATION,
    );
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementationAsOfBlock",
      "70",
    );
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementationFromLog",
      "true",
    );
    assert.fieldEquals("Contract", VAULT_BEACON, "firstIndexedBlock", "50");
    assert.fieldEquals("OwnershipTransfer", rowKey(0), "newOwner", ALICE);
    assert.fieldEquals(
      "BeaconUpgrade",
      rowKey(1),
      "implementation",
      IMPLEMENTATION,
    );
  });

  test("an orchestrator beacon is its own BEACON row", () => {
    handleOrchestratorBeaconOwnershipTransferred(
      changetype<OrchestratorBeaconOwnershipTransferred>(
        ownershipTransferredLog(
          Address.fromString(ORCHESTRATOR_BEACON),
          Address.fromString(ZERO),
          Address.fromString(BOB),
          50,
          0,
        ),
      ),
    );
    handleOrchestratorBeaconUpgraded(
      changetype<OrchestratorBeaconUpgraded>(
        upgradedLog(
          Address.fromString(ORCHESTRATOR_BEACON),
          Address.fromString(IMPLEMENTATION),
          70,
          1,
        ),
      ),
    );
    transferBeaconOwnership(ZERO, ALICE, 50, 2);

    assert.entityCount("Contract", 2);
    assert.fieldEquals("Contract", ORCHESTRATOR_BEACON, "kind", "BEACON");
    assert.fieldEquals("Contract", ORCHESTRATOR_BEACON, "owner", BOB);
    assert.fieldEquals(
      "Contract",
      ORCHESTRATOR_BEACON,
      "implementation",
      IMPLEMENTATION,
    );
    assert.fieldEquals("Contract", BEACON, "owner", ALICE);
  });
});

describe("An upgrade as a beacon's first sighting", () => {
  afterEach(clearStore);

  test("a vault beacon upgrade creates the row as a beacon", () => {
    handleVaultBeaconUpgraded(
      changetype<VaultBeaconUpgraded>(
        upgradedLog(
          Address.fromString(VAULT_BEACON),
          Address.fromString(IMPLEMENTATION),
          70,
          1,
        ),
      ),
    );

    assert.entityCount("Contract", 1);
    assert.fieldEquals("Contract", VAULT_BEACON, "kind", "BEACON");
    assert.fieldEquals("Contract", VAULT_BEACON, "firstIndexedBlock", "70");
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementation",
      IMPLEMENTATION,
    );
    assert.fieldEquals(
      "Contract",
      VAULT_BEACON,
      "implementationFromLog",
      "true",
    );
    assert.fieldEquals("Contract", VAULT_BEACON, "ownerFromLog", "false");
  });
});
