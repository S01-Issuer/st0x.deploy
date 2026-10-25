import { Bytes, ethereum, log } from "@graphprotocol/graph-ts";
import {
  CallExecuted,
  CallSalt,
  CallScheduled,
  Cancelled,
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
} from "../generated/GovernanceTimelock/TimelockController";
import {
  TimelockCall,
  TimelockOperation,
  TimelockOperationKey,
} from "../generated/schema";
import { recordRoleAdminChange, recordRoleGrant } from "./lib/accesscontrol";
import { ContractKind, getOrCreateContract } from "./lib/contract";

/**
 * The values of the schema's `TimelockOperationStatus` enum, written out for
 * the same reason as `ContractKind`: codegen renders the field as a `string`.
 */
export namespace TimelockOperationStatus {
  export const PENDING = "PENDING";
  export const EXECUTED = "EXECUTED";
  export const CANCELLED = "CANCELLED";
}

/** `bytes32(0)`: the salt of an operation no `CallSalt` was emitted for. */
function zeroSalt(): Bytes {
  return Bytes.fromHexString(
    "0x0000000000000000000000000000000000000000000000000000000000000000",
  );
}

/** `TimelockOperationKey.id`: the timelock address followed by the operation id. */
export function timelockOperationKeyId(
  timelock: Bytes,
  operationId: Bytes,
): Bytes {
  return timelock.concat(operationId);
}

/** `TimelockOperation.id`: the key id followed by the scheduling index. */
export function timelockOperationId(
  keyId: Bytes,
  schedulingIndex: i32,
): Bytes {
  return keyId.concatI32(schedulingIndex);
}

/** `TimelockCall.id`: the operation id followed by the call index. */
export function timelockCallId(operation: Bytes, index: i32): Bytes {
  return operation.concatI32(index);
}

/**
 * The latest scheduling of `operationId` on the emitting timelock, or null when
 * the id has never been scheduled here. OpenZeppelin only emits `CallSalt`,
 * `CallExecuted` and `Cancelled` for an id it holds a timestamp for, which only
 * `CallScheduled` sets, and every data source starts at or below the timelock's
 * creation block, so a null here means the index is missing history. That is
 * logged rather than thrown, because throwing would halt the whole subgraph.
 */
function latestOperation(
  event: ethereum.Event,
  operationId: Bytes,
  eventName: string,
): TimelockOperation | null {
  let key = TimelockOperationKey.load(
    timelockOperationKeyId(event.address, operationId),
  );
  if (key === null) {
    log.warning("{} for unscheduled timelock operation {} on {} in tx {}", [
      eventName,
      operationId.toHexString(),
      event.address.toHexString(),
      event.transaction.hash.toHexString(),
    ]);
    return null;
  }
  return TimelockOperation.load(key.latest);
}

/**
 * Open a new scheduling of the id for an index-0 `CallScheduled`, or return the
 * one that log already opened when graph-node hands the same log over again.
 *
 * OpenZeppelin refuses to schedule an id it holds a timestamp for, so an
 * index-0 log is a fresh scheduling unless it is the very log the latest
 * scheduling was opened by. The comparison is on the log's identity, not on the
 * latest scheduling's status, so a replayed log cannot open a second scheduling.
 */
function openOperation(event: CallScheduled): TimelockOperation {
  let timelock = getOrCreateContract(
    event.address,
    ContractKind.GOVERNANCE_TIMELOCK,
    event.block.number,
  );
  let keyId = timelockOperationKeyId(timelock.id, event.params.id);
  let key = TimelockOperationKey.load(keyId);
  if (key !== null) {
    let latest = TimelockOperation.load(key.latest)!;
    if (
      latest.scheduledTransactionHash.equals(event.transaction.hash) &&
      latest.scheduledLogIndex.equals(event.logIndex)
    ) {
      return latest;
    }
  } else {
    key = new TimelockOperationKey(keyId);
    key.timelock = timelock.id;
    key.operationId = event.params.id;
    key.scheduleCount = 0;
  }

  let operation = new TimelockOperation(
    timelockOperationId(keyId, key.scheduleCount),
  );
  operation.timelock = timelock.id;
  operation.key = keyId;
  operation.operationId = event.params.id;
  operation.schedulingIndex = key.scheduleCount;
  operation.status = TimelockOperationStatus.PENDING;
  operation.callCount = 0;
  operation.targets = [];
  operation.predecessor = event.params.predecessor;
  operation.salt = zeroSalt();
  operation.delay = event.params.delay;
  operation.readyAt = event.block.timestamp.plus(event.params.delay);
  operation.scheduledAtBlock = event.block.number;
  operation.scheduledAtTimestamp = event.block.timestamp;
  operation.scheduledTransactionHash = event.transaction.hash;
  operation.scheduledTransactionFrom = event.transaction.from;
  operation.scheduledLogIndex = event.logIndex;
  operation.save();

  key.scheduleCount = key.scheduleCount + 1;
  key.latest = operation.id;
  key.save();
  return operation;
}

/**
 * Whether `list` holds `address`. `Array.includes` compares references, not
 * bytes, so it is no use on `Bytes`.
 */
function containsAddress(list: Array<Bytes>, address: Bytes): boolean {
  for (let i = 0; i < list.length; i++) {
    if (list[i].equals(address)) {
      return true;
    }
  }
  return false;
}

/**
 * Record one `CallScheduled`. Index 0 opens the operation; every later index of
 * a `scheduleBatch` comes from the same transaction, right after it, and adds a
 * call to it.
 */
export function handleTimelockCallScheduled(event: CallScheduled): void {
  let index = event.params.index.toI32();
  let operation: TimelockOperation | null;
  if (index == 0) {
    operation = openOperation(event);
  } else {
    operation = latestOperation(event, event.params.id, "CallScheduled");
    if (operation === null) {
      return;
    }
  }

  let callId = timelockCallId(operation.id, index);
  if (TimelockCall.load(callId) !== null) {
    return;
  }
  let call = new TimelockCall(callId);
  call.operation = operation.id;
  call.index = index;
  call.target = event.params.target;
  call.value = event.params.value;
  call.data = event.params.data;
  call.save();

  operation.callCount = operation.callCount + 1;
  if (!containsAddress(operation.targets, event.params.target)) {
    let targets = operation.targets;
    targets.push(event.params.target);
    operation.targets = targets;
  }
  operation.save();
}

/**
 * Record one `CallSalt`. OpenZeppelin emits it once, after the operation's
 * `CallScheduled` logs and only for a non-zero salt.
 */
export function handleTimelockCallSalt(event: CallSalt): void {
  let operation = latestOperation(event, event.params.id, "CallSalt");
  if (operation === null) {
    return;
  }
  operation.salt = event.params.salt;
  operation.save();
}

/**
 * Record one `CallExecuted`. A batch emits one per call, all from the executing
 * transaction, so every one of them writes the same status and stamps: the
 * operation moves to `EXECUTED` once and the later calls leave it as it is.
 */
export function handleTimelockCallExecuted(event: CallExecuted): void {
  let operation = latestOperation(event, event.params.id, "CallExecuted");
  if (operation === null) {
    return;
  }
  operation.status = TimelockOperationStatus.EXECUTED;
  operation.executedAtBlock = event.block.number;
  operation.executedAtTimestamp = event.block.timestamp;
  operation.executedTransactionHash = event.transaction.hash;
  operation.executedTransactionFrom = event.transaction.from;
  operation.save();
}

/** Record one `Cancelled`. OpenZeppelin only cancels a pending operation. */
export function handleTimelockCancelled(event: Cancelled): void {
  let operation = latestOperation(event, event.params.id, "Cancelled");
  if (operation === null) {
    return;
  }
  operation.status = TimelockOperationStatus.CANCELLED;
  operation.cancelledAtBlock = event.block.number;
  operation.cancelledAtTimestamp = event.block.timestamp;
  operation.cancelledTransactionHash = event.transaction.hash;
  operation.cancelledTransactionFrom = event.transaction.from;
  operation.save();
}

export function handleTimelockRoleGranted(event: RoleGranted): void {
  recordRoleGrant(
    ContractKind.GOVERNANCE_TIMELOCK,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    true,
  );
}

export function handleTimelockRoleRevoked(event: RoleRevoked): void {
  recordRoleGrant(
    ContractKind.GOVERNANCE_TIMELOCK,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    false,
  );
}

export function handleTimelockRoleAdminChanged(event: RoleAdminChanged): void {
  recordRoleAdminChange(
    ContractKind.GOVERNANCE_TIMELOCK,
    event,
    event.params.role,
    event.params.previousAdminRole,
    event.params.newAdminRole,
  );
}
