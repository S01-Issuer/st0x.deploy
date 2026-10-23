import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { TimelockOperation } from "../generated/schema";
import {
  CallExecuted,
  CallSalt,
  CallScheduled,
  Cancelled,
} from "../generated/GovernanceTimelock/TimelockController";
import {
  handleTimelockCallExecuted,
  handleTimelockCallSalt,
  handleTimelockCallScheduled,
  handleTimelockCancelled,
  timelockCallId,
  timelockOperationId,
  timelockOperationKeyId,
} from "../src/timelock";
import {
  TX_FROM,
  TX_HASH,
  callExecutedLog,
  callSaltLog,
  callScheduledLog,
  cancelledLog,
} from "./event-mocks.test";

const TIMELOCK = "0x48ba1371a78e6cc54157c63721756ab444510db3";
const OTHER_TIMELOCK = "0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b";
const ORCHESTRATOR = "0x00000000000000000000000000000000000000c0";
const AUTHORIZER = "0x315b16faa6ee413fabca877d3851b3818369f0cd";
const BEACON = "0x00000000000000000000000000000000000000b1";
const OP = "0x0101010101010101010101010101010101010101010101010101010101010101";
const OTHER_OP =
  "0x0202020202020202020202020202020202020202020202020202020202020202";
const PREDECESSOR =
  "0x0303030303030303030303030303030303030303030303030303030303030303";
const SALT =
  "0x0404040404040404040404040404040404040404040404040404040404040404";
const ZERO_BYTES32 =
  "0x0000000000000000000000000000000000000000000000000000000000000000";
const GRANT_DATA = "0x2f2ff15d";
const REVOKE_DATA = "0xd547741f";
const UPGRADE_DATA = "0x3659cfe6";
const DELAY: i32 = 172800;

/** The transaction an execute or cancel arrives in, distinct from `TX_HASH`. */
const LATER_TX_HASH: Bytes = Bytes.fromHexString(
  "0xdeadbeef00000000000000000000000000000000000000000000000000000002",
);
const LATER_TX_FROM: Address = Address.fromString(
  "0x00000000000000000000000000000000000000ee",
);

function inLaterTx(event: ethereum.Event): ethereum.Event {
  event.transaction.hash = LATER_TX_HASH;
  event.transaction.from = LATER_TX_FROM;
  return event;
}

/** The transaction a second scheduling of the same id arrives in. */
const RESCHEDULE_TX_HASH: Bytes = Bytes.fromHexString(
  "0xdeadbeef00000000000000000000000000000000000000000000000000000003",
);

/**
 * Whether a nullable field is unset. Compares the pointer, because `==` on
 * `BigInt` and `Bytes` is an overloaded operator the compiler cannot apply to
 * `null`.
 */
function isUnset<T>(value: T): boolean {
  return changetype<usize>(value) == 0;
}

function loadOperation(id: string): TimelockOperation {
  return TimelockOperation.load(Bytes.fromHexString(id))!;
}

/** Every execution stamp is unset, which `fieldEquals` cannot check. */
function assertNotExecuted(id: string): void {
  let op = loadOperation(id);
  assert.assertTrue(isUnset(op.executedAtBlock));
  assert.assertTrue(isUnset(op.executedAtTimestamp));
  assert.assertTrue(isUnset(op.executedTransactionHash));
  assert.assertTrue(isUnset(op.executedTransactionFrom));
}

/** Every cancellation stamp is unset. */
function assertNotCancelled(id: string): void {
  let op = loadOperation(id);
  assert.assertTrue(isUnset(op.cancelledAtBlock));
  assert.assertTrue(isUnset(op.cancelledAtTimestamp));
  assert.assertTrue(isUnset(op.cancelledTransactionHash));
  assert.assertTrue(isUnset(op.cancelledTransactionFrom));
}

function schedule(
  timelock: string,
  id: string,
  index: i32,
  target: string,
  data: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  scheduleInTx(
    timelock,
    id,
    index,
    target,
    data,
    blockNumber,
    logIndex,
    TX_HASH,
  );
}

function scheduleInTx(
  timelock: string,
  id: string,
  index: i32,
  target: string,
  data: string,
  blockNumber: i32,
  logIndex: i32,
  txHash: Bytes,
): void {
  let event = callScheduledLog(
    Address.fromString(timelock),
    Bytes.fromHexString(id),
    index,
    Address.fromString(target),
    index + 7,
    Bytes.fromHexString(data),
    Bytes.fromHexString(PREDECESSOR),
    DELAY,
    blockNumber,
    logIndex,
  );
  event.transaction.hash = txHash;
  handleTimelockCallScheduled(changetype<CallScheduled>(event));
}

function execute(
  id: string,
  index: i32,
  target: string,
  data: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleTimelockCallExecuted(
    changetype<CallExecuted>(
      inLaterTx(
        callExecutedLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(id),
          index,
          Address.fromString(target),
          index + 7,
          Bytes.fromHexString(data),
          blockNumber,
          logIndex,
        ),
      ),
    ),
  );
}

function cancel(id: string, blockNumber: i32, logIndex: i32): void {
  handleTimelockCancelled(
    changetype<Cancelled>(
      inLaterTx(
        cancelledLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(id),
          blockNumber,
          logIndex,
        ),
      ),
    ),
  );
}

function salt(
  id: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleTimelockCallSalt(
    changetype<CallSalt>(
      callSaltLog(
        Address.fromString(TIMELOCK),
        Bytes.fromHexString(id),
        Bytes.fromHexString(value),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function keyKey(timelock: string, id: string): Bytes {
  return timelockOperationKeyId(
    Bytes.fromHexString(timelock),
    Bytes.fromHexString(id),
  );
}

function opKey(timelock: string, id: string, scheduling: i32): string {
  return timelockOperationId(keyKey(timelock, id), scheduling).toHexString();
}

function callKey(
  timelock: string,
  id: string,
  scheduling: i32,
  index: i32,
): string {
  return timelockCallId(
    timelockOperationId(keyKey(timelock, id), scheduling),
    index,
  ).toHexString();
}

describe("Scheduling", () => {
  afterEach(clearStore);

  test("a schedule creates a pending operation with its one call", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 4);

    assert.entityCount("TimelockOperationKey", 1);
    assert.entityCount("TimelockOperation", 1);
    assert.entityCount("TimelockCall", 1);
    assert.fieldEquals("Contract", TIMELOCK, "kind", "GOVERNANCE_TIMELOCK");

    let key = keyKey(TIMELOCK, OP).toHexString();
    let op = opKey(TIMELOCK, OP, 0);
    assert.fieldEquals("TimelockOperationKey", key, "timelock", TIMELOCK);
    assert.fieldEquals("TimelockOperationKey", key, "operationId", OP);
    assert.fieldEquals("TimelockOperationKey", key, "scheduleCount", "1");
    assert.fieldEquals("TimelockOperationKey", key, "latest", op);

    assert.fieldEquals("TimelockOperation", op, "timelock", TIMELOCK);
    assert.fieldEquals("TimelockOperation", op, "key", key);
    assert.fieldEquals("TimelockOperation", op, "operationId", OP);
    assert.fieldEquals("TimelockOperation", op, "schedulingIndex", "0");
    assert.fieldEquals("TimelockOperation", op, "status", "PENDING");
    assert.fieldEquals("TimelockOperation", op, "callCount", "1");
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "targets",
      "[" + ORCHESTRATOR + "]",
    );
    assert.fieldEquals("TimelockOperation", op, "predecessor", PREDECESSOR);
    // OpenZeppelin emits `CallSalt` only for a non-zero salt, so until one
    // arrives the salt is zero.
    assert.fieldEquals("TimelockOperation", op, "salt", ZERO_BYTES32);
    assert.fieldEquals("TimelockOperation", op, "delay", "172800");
    // Block 100's mock timestamp is 1200; OpenZeppelin stores 1200 + delay.
    assert.fieldEquals("TimelockOperation", op, "readyAt", "174000");
    assert.fieldEquals("TimelockOperation", op, "scheduledAtBlock", "100");
    assert.fieldEquals("TimelockOperation", op, "scheduledAtTimestamp", "1200");
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "scheduledTransactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "scheduledTransactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("TimelockOperation", op, "scheduledLogIndex", "4");
    assertNotExecuted(op);
    assertNotCancelled(op);

    let call = callKey(TIMELOCK, OP, 0, 0);
    assert.fieldEquals("TimelockCall", call, "operation", op);
    assert.fieldEquals("TimelockCall", call, "index", "0");
    assert.fieldEquals("TimelockCall", call, "target", ORCHESTRATOR);
    assert.fieldEquals("TimelockCall", call, "value", "7");
    assert.fieldEquals("TimelockCall", call, "data", GRANT_DATA);
  });

  test("a CallSalt sets the salt of the operation it names", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 4);
    schedule(TIMELOCK, OTHER_OP, 0, ORCHESTRATOR, REVOKE_DATA, 100, 6);
    salt(OP, SALT, 100, 5);

    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 0),
      "salt",
      SALT,
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OTHER_OP, 0),
      "salt",
      ZERO_BYTES32,
    );
  });

  test("a batch is one operation with a call per CallScheduled", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(TIMELOCK, OP, 1, AUTHORIZER, REVOKE_DATA, 100, 2);
    schedule(TIMELOCK, OP, 2, ORCHESTRATOR, REVOKE_DATA, 100, 3);
    salt(OP, SALT, 100, 4);

    assert.entityCount("TimelockOperationKey", 1);
    assert.entityCount("TimelockOperation", 1);
    assert.entityCount("TimelockCall", 3);

    let op = opKey(TIMELOCK, OP, 0);
    assert.fieldEquals("TimelockOperation", op, "callCount", "3");
    // Two calls target the orchestrator; it is listed once.
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "targets",
      "[" + ORCHESTRATOR + ", " + AUTHORIZER + "]",
    );
    assert.fieldEquals("TimelockOperation", op, "salt", SALT);
    // Every stamp comes from the index-0 log that opened the operation.
    assert.fieldEquals("TimelockOperation", op, "scheduledLogIndex", "1");

    let second = callKey(TIMELOCK, OP, 0, 1);
    assert.fieldEquals("TimelockCall", second, "operation", op);
    assert.fieldEquals("TimelockCall", second, "index", "1");
    assert.fieldEquals("TimelockCall", second, "target", AUTHORIZER);
    assert.fieldEquals("TimelockCall", second, "value", "8");
    assert.fieldEquals("TimelockCall", second, "data", REVOKE_DATA);
    assert.fieldEquals(
      "TimelockCall",
      callKey(TIMELOCK, OP, 0, 2),
      "target",
      ORCHESTRATOR,
    );
  });

  test("replaying a batch's logs adds no scheduling and no call", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(TIMELOCK, OP, 1, AUTHORIZER, REVOKE_DATA, 100, 2);
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(TIMELOCK, OP, 1, AUTHORIZER, REVOKE_DATA, 100, 2);

    assert.entityCount("TimelockOperation", 1);
    assert.entityCount("TimelockCall", 2);
    assert.fieldEquals(
      "TimelockOperationKey",
      keyKey(TIMELOCK, OP).toHexString(),
      "scheduleCount",
      "1",
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 0),
      "callCount",
      "2",
    );
  });

  test("the same id on two timelocks is two operations", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(OTHER_TIMELOCK, OP, 0, BEACON, UPGRADE_DATA, 100, 2);

    assert.entityCount("Contract", 2);
    assert.entityCount("TimelockOperationKey", 2);
    assert.entityCount("TimelockOperation", 2);
    assert.fieldEquals(
      "TimelockOperation",
      opKey(OTHER_TIMELOCK, OP, 0),
      "timelock",
      OTHER_TIMELOCK,
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(OTHER_TIMELOCK, OP, 0),
      "targets",
      "[" + BEACON + "]",
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 0),
      "targets",
      "[" + ORCHESTRATOR + "]",
    );
  });
});

describe("Execution", () => {
  afterEach(clearStore);

  test("an execute marks the operation executed with its own transaction", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    execute(OP, 0, ORCHESTRATOR, GRANT_DATA, 20000, 3);

    let op = opKey(TIMELOCK, OP, 0);
    assert.fieldEquals("TimelockOperation", op, "status", "EXECUTED");
    assert.fieldEquals("TimelockOperation", op, "executedAtBlock", "20000");
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "executedAtTimestamp",
      "240000",
    );
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "executedTransactionHash",
      LATER_TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "executedTransactionFrom",
      LATER_TX_FROM.toHexString(),
    );
    // The schedule stamps are the scheduling transaction's, not the executor's.
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "scheduledTransactionHash",
      TX_HASH.toHexString(),
    );
    assertNotCancelled(op);
    assert.entityCount("TimelockOperation", 1);
    assert.entityCount("TimelockCall", 1);
  });

  test("executing a batch moves its one operation to executed", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(TIMELOCK, OP, 1, AUTHORIZER, REVOKE_DATA, 100, 2);
    schedule(TIMELOCK, OP, 2, BEACON, UPGRADE_DATA, 100, 3);
    execute(OP, 0, ORCHESTRATOR, GRANT_DATA, 20000, 5);
    execute(OP, 1, AUTHORIZER, REVOKE_DATA, 20000, 6);
    execute(OP, 2, BEACON, UPGRADE_DATA, 20000, 7);

    let op = opKey(TIMELOCK, OP, 0);
    assert.entityCount("TimelockOperation", 1);
    assert.entityCount("TimelockCall", 3);
    assert.fieldEquals("TimelockOperation", op, "status", "EXECUTED");
    assert.fieldEquals("TimelockOperation", op, "executedAtBlock", "20000");
    assert.fieldEquals("TimelockOperation", op, "callCount", "3");
    assert.fieldEquals(
      "TimelockOperationKey",
      keyKey(TIMELOCK, OP).toHexString(),
      "scheduleCount",
      "1",
    );
  });

  test("an execute leaves other pending operations pending", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(TIMELOCK, OTHER_OP, 0, ORCHESTRATOR, REVOKE_DATA, 100, 2);
    execute(OP, 0, ORCHESTRATOR, GRANT_DATA, 20000, 3);

    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OTHER_OP, 0),
      "status",
      "PENDING",
    );
    assertNotExecuted(opKey(TIMELOCK, OTHER_OP, 0));
  });
});

describe("Cancellation", () => {
  afterEach(clearStore);

  test("a cancel marks the operation cancelled with its own transaction", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    schedule(TIMELOCK, OTHER_OP, 0, ORCHESTRATOR, REVOKE_DATA, 100, 2);
    cancel(OP, 150, 9);

    let op = opKey(TIMELOCK, OP, 0);
    assert.fieldEquals("TimelockOperation", op, "status", "CANCELLED");
    assert.fieldEquals("TimelockOperation", op, "cancelledAtBlock", "150");
    assert.fieldEquals("TimelockOperation", op, "cancelledAtTimestamp", "1800");
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "cancelledTransactionHash",
      LATER_TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "TimelockOperation",
      op,
      "cancelledTransactionFrom",
      LATER_TX_FROM.toHexString(),
    );
    assertNotExecuted(op);
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OTHER_OP, 0),
      "status",
      "PENDING",
    );
  });

  test("rescheduling a cancelled id opens a second scheduling", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    cancel(OP, 150, 9);
    scheduleInTx(
      TIMELOCK,
      OP,
      0,
      ORCHESTRATOR,
      GRANT_DATA,
      200,
      1,
      RESCHEDULE_TX_HASH,
    );

    let key = keyKey(TIMELOCK, OP).toHexString();
    let first = opKey(TIMELOCK, OP, 0);
    let second = opKey(TIMELOCK, OP, 1);
    assert.entityCount("TimelockOperationKey", 1);
    assert.entityCount("TimelockOperation", 2);
    assert.entityCount("TimelockCall", 2);
    assert.fieldEquals("TimelockOperationKey", key, "scheduleCount", "2");
    assert.fieldEquals("TimelockOperationKey", key, "latest", second);

    // The cancelled scheduling stays as history.
    assert.fieldEquals("TimelockOperation", first, "status", "CANCELLED");
    assert.fieldEquals("TimelockOperation", second, "status", "PENDING");
    assert.fieldEquals("TimelockOperation", second, "schedulingIndex", "1");
    assert.fieldEquals("TimelockOperation", second, "scheduledAtBlock", "200");
    assert.fieldEquals("TimelockOperation", second, "readyAt", "175200");
    assertNotCancelled(second);
    assert.fieldEquals(
      "TimelockCall",
      callKey(TIMELOCK, OP, 1, 0),
      "operation",
      second,
    );
  });

  // A Safe `MultiSend` can cancel an operation and schedule the same calls again
  // in one transaction, so both index-0 logs share a transaction hash and only
  // the log index tells them apart.
  test("a cancel and reschedule in one transaction is two schedulings", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    handleTimelockCancelled(
      changetype<Cancelled>(
        cancelledLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(OP),
          100,
          2,
        ),
      ),
    );
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 3);

    assert.entityCount("TimelockOperation", 2);
    assert.fieldEquals(
      "TimelockOperationKey",
      keyKey(TIMELOCK, OP).toHexString(),
      "scheduleCount",
      "2",
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 0),
      "status",
      "CANCELLED",
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 1),
      "status",
      "PENDING",
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 1),
      "scheduledLogIndex",
      "3",
    );
  });

  test("an execute after a reschedule lands on the new scheduling", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    cancel(OP, 150, 9);
    scheduleInTx(
      TIMELOCK,
      OP,
      0,
      ORCHESTRATOR,
      GRANT_DATA,
      200,
      1,
      RESCHEDULE_TX_HASH,
    );
    execute(OP, 0, ORCHESTRATOR, GRANT_DATA, 20000, 3);

    let first = opKey(TIMELOCK, OP, 0);
    let second = opKey(TIMELOCK, OP, 1);
    assert.fieldEquals("TimelockOperation", first, "status", "CANCELLED");
    assertNotExecuted(first);
    assert.fieldEquals("TimelockOperation", second, "status", "EXECUTED");
    assert.fieldEquals("TimelockOperation", second, "executedAtBlock", "20000");
  });

  test("a CallSalt after a reschedule lands on the new scheduling", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    cancel(OP, 150, 9);
    scheduleInTx(
      TIMELOCK,
      OP,
      0,
      ORCHESTRATOR,
      GRANT_DATA,
      200,
      1,
      RESCHEDULE_TX_HASH,
    );
    salt(OP, SALT, 200, 2);

    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 0),
      "salt",
      ZERO_BYTES32,
    );
    assert.fieldEquals(
      "TimelockOperation",
      opKey(TIMELOCK, OP, 1),
      "salt",
      SALT,
    );
  });
});

describe("Events for an id never scheduled", () => {
  afterEach(clearStore);

  test("write nothing", () => {
    schedule(TIMELOCK, OP, 1, ORCHESTRATOR, GRANT_DATA, 100, 1);
    salt(OP, SALT, 100, 2);
    execute(OP, 0, ORCHESTRATOR, GRANT_DATA, 20000, 3);
    cancel(OP, 150, 4);

    assert.entityCount("Contract", 0);
    assert.entityCount("TimelockOperationKey", 0);
    assert.entityCount("TimelockOperation", 0);
    assert.entityCount("TimelockCall", 0);
  });
});

describe("Timelock operation row ids", () => {
  afterEach(clearStore);

  // Written out from the schema's definitions rather than built with the id
  // helpers, which would move with any layout change they were meant to catch.
  // The scheduling and call indices are appended by `concatI32`, which writes
  // the `int32` little-endian.
  test("key, operation and call ids are the documented byte layout", () => {
    schedule(TIMELOCK, OP, 0, ORCHESTRATOR, GRANT_DATA, 100, 1);
    cancel(OP, 150, 9);
    scheduleInTx(
      TIMELOCK,
      OP,
      0,
      ORCHESTRATOR,
      GRANT_DATA,
      200,
      1,
      RESCHEDULE_TX_HASH,
    );
    scheduleInTx(
      TIMELOCK,
      OP,
      1,
      AUTHORIZER,
      REVOKE_DATA,
      200,
      2,
      RESCHEDULE_TX_HASH,
    );

    let key =
      "0x48ba1371a78e6cc54157c63721756ab444510db30101010101010101010101010101010101010101010101010101010101010101";
    assert.fieldEquals("TimelockOperationKey", key, "scheduleCount", "2");
    assert.fieldEquals(
      "TimelockOperation",
      key + "01000000",
      "schedulingIndex",
      "1",
    );
    assert.fieldEquals(
      "TimelockCall",
      key + "01000000" + "01000000",
      "target",
      AUTHORIZER,
    );
  });
});
