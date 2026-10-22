import { Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  RegistryDelegate,
  RegistryDelegateChange,
} from "../../generated/schema";
import { getOrCreateContract } from "./contract";
import { logRowId } from "./event";

/** `RegistryDelegate.id`: registry ++ account ++ the `bytes32` scope ++ delegate. */
export function registryDelegateId(
  registry: Bytes,
  account: Bytes,
  scope: Bytes,
  delegate: Bytes,
): Bytes {
  return registry.concat(account).concat(scope).concat(delegate);
}

/**
 * Record one `IRegistryDelegatesV1` `Approved` (`approved` true) or `Revoked`
 * (false). Both registries emit either log whatever the prior state, so the log
 * sets `approved` rather than toggling it. A replay of a log already recorded
 * returns before touching the approval, so an older log cannot roll it back.
 */
export function recordDelegateChange(
  kind: string,
  event: ethereum.Event,
  account: Bytes,
  scope: Bytes,
  delegate: Bytes,
  approved: boolean,
): void {
  let rowId = logRowId(event);
  if (RegistryDelegateChange.load(rowId) !== null) {
    return;
  }
  let registry = getOrCreateContract(event.address, kind, event.block.number);
  let id = registryDelegateId(registry.id, account, scope, delegate);
  let entity = RegistryDelegate.load(id);
  if (entity === null) {
    entity = new RegistryDelegate(id);
    entity.registry = registry.id;
    entity.account = account;
    entity.scope = scope;
    entity.delegate = delegate;
  }
  entity.approved = approved;
  if (approved) {
    entity.approvedAtBlock = event.block.number;
    entity.approvedAtTimestamp = event.block.timestamp;
  } else {
    entity.revokedAtBlock = event.block.number;
    entity.revokedAtTimestamp = event.block.timestamp;
  }
  entity.save();

  let row = new RegistryDelegateChange(rowId);
  row.registryDelegate = id;
  row.approved = approved;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}
