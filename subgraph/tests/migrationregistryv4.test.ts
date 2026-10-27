import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes } from "@graphprotocol/graph-ts";
import { MigrationRecord, RegistryMeta } from "../generated/schema";
import { Migrated } from "../generated/MigrationRegistry/MigrationRegistry";
import {
  Approved,
  MetaV1_2,
  Migrated as MigratedV4,
  Revoked,
} from "../generated/MigrationRegistryV4/MigrationRegistryV4";
import {
  handleMigrationRegistryMigrated,
  handleMigrationRegistryV4Approved,
  handleMigrationRegistryV4MetaV1_2,
  handleMigrationRegistryV4Migrated,
  handleMigrationRegistryV4Revoked,
} from "../src/migrationregistry";
import {
  delegateChangeLog,
  metaV1_2Log,
  migratedLog,
  mockRowId,
  TX_FROM,
  TX_HASH,
} from "./event-mocks.test";

const REGISTRY = "0x1a4b89828eb2dd5f3a353bd98472512f371ce408";
const REGISTRY_V3 = "0x5a48e719785e11c4643ea4056d0861a6a69e91a0";
/** st0x `LibStoxMigrations.WRITER`. */
const WRITER = "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
const SAFE = "0x00000000000000000000000000000000000000d1";
/** `keccak256("st0x.deploy")`, from `cast keccak`: `LibStoxMigrations.NAMESPACE`. */
const NAMESPACE =
  "0xd9cec8396b568ba46ea521970e5edeac9163854e75287e989c213c3e9e84bda4";
/** `MIGRATION_HEAD_GENESIS`, from `cast keccak`. */
const GENESIS =
  "0xd85a7f14bb19a07649810ac09029cc9c29667e4059cb83e258bc52e213365d3f";
const MIGRATION_1 =
  "0x0000000000000000000000000000000000000000000000000000000000000001";
const MIGRATION_2 =
  "0x0000000000000000000000000000000000000000000000000000000000000002";
/** `keccak256(abi.encode(WRITER, NAMESPACE, MIGRATION_1))`, from `cast keccak $(cast abi-encode "f(address,bytes32,bytes32)" …)`. */
const SUBJECT_1 =
  "0x0b7c43b417d2da831de8bf4c0ddf35ac27334572da1b915eb3863a9b7f65fe6a";
/** An empty rain meta document: just the `RainMetaDocumentV1` magic. */
const META = "0xff0a89c674ee7874";

function lineId(registry: string): string {
  return registry.concat(WRITER.slice(2)).concat(NAMESPACE.slice(2));
}

function migrate(migration: string, blockNumber: i32, logIndex: i32): void {
  handleMigrationRegistryV4Migrated(
    changetype<MigratedV4>(
      migratedLog(
        Address.fromString(REGISTRY),
        Address.fromString(SAFE),
        Address.fromString(WRITER),
        Bytes.fromHexString(NAMESPACE),
        Bytes.fromHexString(migration),
        1000,
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function meta(subject: string, blockNumber: i32, logIndex: i32): void {
  handleMigrationRegistryV4MetaV1_2(
    changetype<MetaV1_2>(
      metaV1_2Log(
        Address.fromString(REGISTRY),
        Address.fromString(SAFE),
        Bytes.fromHexString(subject),
        Bytes.fromHexString(META),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

describe("MigrationRegistryV4 Migrated", () => {
  afterEach(clearStore);

  test("a first Migrated records onto genesis under the V4 registry, with its meta subject", () => {
    migrate(MIGRATION_1, 100, 2);

    let row = mockRowId(2);
    assert.fieldEquals("MigrationRecord", row, "line", lineId(REGISTRY));
    assert.fieldEquals("MigrationRecord", row, "index", "0");
    assert.fieldEquals("MigrationRecord", row, "migration", MIGRATION_1);
    assert.fieldEquals("MigrationRecord", row, "appliedOnto", GENESIS);
    assert.fieldEquals("MigrationRecord", row, "appliedAt", "1000");
    assert.fieldEquals("MigrationRecord", row, "sender", SAFE);
    assert.fieldEquals("MigrationRecord", row, "metaSubject", SUBJECT_1);
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "head", MIGRATION_1);
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "recordCount", "1");
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY_V4");
  });

  test("a second Migrated chains onto the first and a replay counts once", () => {
    migrate(MIGRATION_1, 100, 2);
    migrate(MIGRATION_2, 101, 0);
    migrate(MIGRATION_2, 101, 0);

    assert.fieldEquals("MigrationRecord", mockRowId(0), "index", "1");
    assert.fieldEquals(
      "MigrationRecord",
      mockRowId(0),
      "appliedOnto",
      MIGRATION_1,
    );
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "head", MIGRATION_2);
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "recordCount", "2");
    assert.entityCount("MigrationRecord", 2);
  });

  test("a V3 line of the same writer and namespace is its own line, with no meta subject", () => {
    handleMigrationRegistryMigrated(
      changetype<Migrated>(
        migratedLog(
          Address.fromString(REGISTRY_V3),
          Address.fromString(SAFE),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Bytes.fromHexString(MIGRATION_1),
          1000,
          90,
          5,
        ),
      ),
    );
    migrate(MIGRATION_1, 100, 2);

    assert.entityCount("MigrationLine", 2);
    assert.fieldEquals(
      "MigrationLine",
      lineId(REGISTRY_V3),
      "recordCount",
      "1",
    );
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "recordCount", "1");
    assert.fieldEquals("Contract", REGISTRY_V3, "kind", "MIGRATION_REGISTRY");
    let v3 = MigrationRecord.load(Bytes.fromHexString(mockRowId(5)))!;
    assert.assertTrue(v3.metaSubject === null);
  });
});

describe("MigrationRegistryV4 MetaV1_2", () => {
  afterEach(clearStore);

  test("a write's meta links to its record, raw and unverified", () => {
    migrate(MIGRATION_1, 100, 2);
    meta(SUBJECT_1, 100, 3);

    let row = mockRowId(3);
    assert.entityCount("RegistryMeta", 1);
    assert.fieldEquals("RegistryMeta", row, "registry", REGISTRY);
    assert.fieldEquals("RegistryMeta", row, "sender", SAFE);
    assert.fieldEquals("RegistryMeta", row, "subject", SUBJECT_1);
    assert.fieldEquals("RegistryMeta", row, "meta", META);
    assert.fieldEquals("RegistryMeta", row, "migrationRecord", mockRowId(2));
    assert.fieldEquals("RegistryMeta", row, "verified", "false");
    assert.fieldEquals("RegistryMeta", row, "blockNumber", "100");
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("RegistryMeta", row, "logIndex", "3");
    let entity = RegistryMeta.load(Bytes.fromHexString(row))!;
    assert.assertTrue(entity.configBinding === null);
    assert.assertTrue(entity.configRegister === null);
  });

  test("a meta whose subject no record has is kept, unlinked", () => {
    migrate(MIGRATION_1, 100, 2);
    meta(MIGRATION_2, 100, 3);

    let entity = RegistryMeta.load(Bytes.fromHexString(mockRowId(3)))!;
    assert.assertTrue(entity.migrationRecord === null);
    assert.fieldEquals("RegistryMeta", mockRowId(3), "meta", META);
  });

  test("a replayed meta writes one row", () => {
    migrate(MIGRATION_1, 100, 2);
    meta(SUBJECT_1, 100, 3);
    meta(SUBJECT_1, 100, 3);

    assert.entityCount("RegistryMeta", 1);
  });
});

describe("MigrationRegistryV4 delegates", () => {
  afterEach(clearStore);

  test("Approved then Revoked move an approval under the V4 registry", () => {
    handleMigrationRegistryV4Approved(
      changetype<Approved>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Address.fromString(SAFE),
          300,
          4,
        ),
      ),
    );
    let id = REGISTRY.concat(WRITER.slice(2))
      .concat(NAMESPACE.slice(2))
      .concat(SAFE.slice(2));
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY_V4");

    handleMigrationRegistryV4Revoked(
      changetype<Revoked>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Address.fromString(SAFE),
          400,
          2,
        ),
      ),
    );
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryDelegateChange", 2);
  });
});
