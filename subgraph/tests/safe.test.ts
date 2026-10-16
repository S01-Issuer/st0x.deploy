import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address } from "@graphprotocol/graph-ts";
import {
  AddedOwner,
  ChangedThreshold,
  RemovedOwner,
  SafeSetup,
} from "../generated/TokenOwnerSafe/Safe";
import {
  handleSafeAddedOwner,
  handleSafeChangedThreshold,
  handleSafeRemovedOwner,
  handleSafeSetup,
} from "../src/safe";
import {
  TX_HASH,
  changedThresholdLog,
  ownerChangeLog,
  safeSetupLog,
} from "./event-mocks.test";

const SAFE = "0x3840aedaec8e82f79d8f6a8f6adca271e13e0329";
const ALICE = "0x00000000000000000000000000000000000000a1";
const BOB = "0x00000000000000000000000000000000000000b0";
const CAROL = "0x00000000000000000000000000000000000000c0";

function setup(threshold: i32, blockNumber: i32, logIndex: i32): void {
  handleSafeSetup(
    changetype<SafeSetup>(
      safeSetupLog(
        Address.fromString(SAFE),
        [Address.fromString(ALICE), Address.fromString(BOB)],
        threshold,
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function changeThreshold(
  threshold: i32,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleSafeChangedThreshold(
    changetype<ChangedThreshold>(
      changedThresholdLog(
        Address.fromString(SAFE),
        threshold,
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function rowKey(logIndex: i32): string {
  return TX_HASH.concatI32(logIndex).toHexString();
}

describe("Token-owner Safe", () => {
  afterEach(clearStore);

  test("setup records the creation threshold and every creation owner", () => {
    setup(1, 10, 3);

    assert.fieldEquals("Contract", SAFE, "kind", "TOKEN_OWNER_SAFE");
    assert.fieldEquals("Contract", SAFE, "threshold", "1");
    assert.fieldEquals("Contract", SAFE, "thresholdAsOfBlock", "10");
    assert.fieldEquals("Contract", SAFE, "safeOwners", `[${ALICE}, ${BOB}]`);
    assert.entityCount("SafeThresholdChange", 1);
    assert.fieldEquals("SafeThresholdChange", rowKey(3), "threshold", "1");
    assert.fieldEquals("SafeThresholdChange", rowKey(3), "setup", "true");
    assert.entityCount("SafeOwnerChange", 2);
    let first = TX_HASH.concatI32(3).concatI32(0).toHexString();
    let second = TX_HASH.concatI32(3).concatI32(1).toHexString();
    assert.fieldEquals("SafeOwnerChange", first, "owner", ALICE);
    assert.fieldEquals("SafeOwnerChange", second, "owner", BOB);
    assert.fieldEquals("SafeOwnerChange", second, "added", "true");
    assert.fieldEquals("SafeOwnerChange", second, "setup", "true");
  });

  test("a threshold change moves the current threshold and keeps history", () => {
    setup(1, 10, 3);
    changeThreshold(3, 20, 7);

    assert.fieldEquals("Contract", SAFE, "threshold", "3");
    assert.fieldEquals("Contract", SAFE, "thresholdAsOfBlock", "20");
    assert.entityCount("SafeThresholdChange", 2);
    assert.fieldEquals("SafeThresholdChange", rowKey(7), "threshold", "3");
    assert.fieldEquals("SafeThresholdChange", rowKey(7), "setup", "false");
    assert.fieldEquals("SafeThresholdChange", rowKey(7), "blockNumber", "20");
    assert.fieldEquals("SafeThresholdChange", rowKey(7), "blockTimestamp", "240");
    assert.fieldEquals("SafeThresholdChange", rowKey(3), "threshold", "1");
  });

  test("owners added and removed move the current set and keep history", () => {
    setup(1, 10, 3);
    handleSafeAddedOwner(
      changetype<AddedOwner>(
        ownerChangeLog(Address.fromString(SAFE), Address.fromString(CAROL), 20, 1),
      ),
    );
    handleSafeRemovedOwner(
      changetype<RemovedOwner>(
        ownerChangeLog(Address.fromString(SAFE), Address.fromString(ALICE), 21, 2),
      ),
    );

    assert.fieldEquals("Contract", SAFE, "safeOwners", `[${BOB}, ${CAROL}]`);
    assert.entityCount("SafeOwnerChange", 4);
    assert.fieldEquals("SafeOwnerChange", rowKey(1), "owner", CAROL);
    assert.fieldEquals("SafeOwnerChange", rowKey(1), "added", "true");
    assert.fieldEquals("SafeOwnerChange", rowKey(1), "setup", "false");
    assert.fieldEquals("SafeOwnerChange", rowKey(2), "owner", ALICE);
    assert.fieldEquals("SafeOwnerChange", rowKey(2), "added", "false");
  });

  test("a threshold change seen before setup still creates the Safe row", () => {
    changeThreshold(3, 20, 7);

    assert.fieldEquals("Contract", SAFE, "kind", "TOKEN_OWNER_SAFE");
    assert.fieldEquals("Contract", SAFE, "firstIndexedBlock", "20");
    assert.fieldEquals("Contract", SAFE, "threshold", "3");
  });
});
