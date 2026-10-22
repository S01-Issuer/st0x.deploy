import { ByteArray, Bytes, crypto } from "@graphprotocol/graph-ts";
import {
  Approved,
  Migrated,
  Revoked,
} from "../generated/MigrationRegistry/MigrationRegistry";
import { MigrationLine, MigrationRecord } from "../generated/schema";
import { ContractKind, getOrCreateContract } from "./lib/contract";
import { logRowId } from "./lib/event";
import { recordDelegateChange } from "./lib/registry";

/** `MIGRATION_HEAD_GENESIS`: the head of a line with no records. */
export function migrationHeadGenesis(): Bytes {
  return Bytes.fromByteArray(
    crypto.keccak256(
      ByteArray.fromUTF8("rain.migration-registry.head.genesis"),
    ),
  );
}

/** `MigrationLine.id`: registry ++ writer ++ the `bytes32` namespace. */
export function migrationLineId(
  registry: Bytes,
  writer: Bytes,
  namespace: Bytes,
): Bytes {
  return registry.concat(writer).concat(namespace);
}

/**
 * Record one `Migrated` as the next record in its line. The registry refuses
 * any write not applied onto the line's current head, so log order is line
 * order: the record's `appliedOnto` is the head before it and it becomes the
 * new head.
 */
export function handleMigrationRegistryMigrated(event: Migrated): void {
  let rowId = logRowId(event);
  let registry = getOrCreateContract(
    event.address,
    ContractKind.MIGRATION_REGISTRY,
    event.block.number,
  );
  let id = migrationLineId(
    registry.id,
    event.params.writer,
    event.params.namespace,
  );
  let line = MigrationLine.load(id);
  let appliedOnto = migrationHeadGenesis();
  let index = 0;
  if (line === null) {
    line = new MigrationLine(id);
    line.registry = registry.id;
    line.writer = event.params.writer;
    line.namespace = event.params.namespace;
  } else {
    appliedOnto = line.head;
    index = line.recordCount;
  }

  let row = new MigrationRecord(rowId);
  row.line = id;
  row.index = index;
  row.migration = event.params.migration;
  row.appliedOnto = appliedOnto;
  row.appliedAt = event.params.appliedAt;
  row.sender = event.params.sender;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();

  line.head = event.params.migration;
  line.headRecord = rowId;
  line.recordCount = index + 1;
  line.save();
}

export function handleMigrationRegistryApproved(event: Approved): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleMigrationRegistryRevoked(event: Revoked): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    false,
  );
}
