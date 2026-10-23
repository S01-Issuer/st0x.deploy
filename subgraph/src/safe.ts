import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  AddedOwner,
  ChangedThreshold,
  RemovedOwner,
  SafeSetup,
} from "../generated/TokenOwnerSafe/Safe";
import {
  AddedOwner1 as AddedOwner130,
  RemovedOwner1 as RemovedOwner130,
} from "../generated/TokenOwnerSafe/Safe";
import {
  Contract,
  SafeOwnerChange,
  SafeThresholdChange,
} from "../generated/schema";
import { ContractKind, getOrCreateContract } from "./lib/contract";
import { logRowId } from "./lib/event";

function safeContract(event: ethereum.Event): Contract {
  return getOrCreateContract(
    event.address,
    ContractKind.TOKEN_OWNER_SAFE,
    event.block.number,
  );
}

function recordThreshold(
  event: ethereum.Event,
  threshold: BigInt,
  setup: boolean,
): void {
  let contract = safeContract(event);
  // setupModules runs before SafeSetup is emitted, so a ChangedThreshold
  // already seen for this Safe is later state than the setup threshold.
  if (!setup || contract.thresholdAsOfBlock === null) {
    contract.threshold = threshold;
    contract.thresholdAsOfBlock = event.block.number;
    contract.save();
  }

  let row = new SafeThresholdChange(logRowId(event));
  row.contract = contract.id;
  row.threshold = threshold;
  row.setup = setup;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

function recordOwner(
  event: ethereum.Event,
  id: Bytes,
  owner: Bytes,
  added: boolean,
  setup: boolean,
): void {
  let row = new SafeOwnerChange(id);
  row.contract = event.address;
  row.owner = owner;
  row.added = added;
  row.setup = setup;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

function withOwner(owners: Array<Bytes>, owner: Bytes): Array<Bytes> {
  let next = owners.slice(0);
  next.push(owner);
  return next;
}

function withoutOwner(owners: Array<Bytes>, owner: Bytes): Array<Bytes> {
  let kept = new Array<Bytes>();
  for (let i = 0; i < owners.length; i++) {
    if (!owners[i].equals(owner)) kept.push(owners[i]);
  }
  return kept;
}

function currentOwners(contract: Contract): Array<Bytes> {
  let owners = contract.safeOwners;
  return owners === null ? new Array<Bytes>() : owners;
}

export function handleSafeSetup(event: SafeSetup): void {
  let contract = safeContract(event);
  let owners = new Array<Bytes>();
  for (let i = 0; i < event.params.owners.length; i++) {
    let owner = event.params.owners[i] as Bytes;
    owners.push(owner);
    recordOwner(event, logRowId(event).concatI32(i), owner, true, true);
  }
  // setupModules runs before SafeSetup is emitted: replay this transaction's
  // earlier owner changes for this Safe onto the setup owners, in log order.
  let setupIndex = event.logIndex.toI32();
  for (let i = 0; i < setupIndex; i++) {
    let change = SafeOwnerChange.load(event.transaction.hash.concatI32(i));
    if (
      change === null ||
      change.setup ||
      !change.contract.equals(event.address)
    ) {
      continue;
    }
    owners = change.added
      ? withOwner(owners, change.owner)
      : withoutOwner(owners, change.owner);
  }
  contract.safeOwners = owners;
  contract.save();
  recordThreshold(event, event.params.threshold, true);
}

function addOwner(event: ethereum.Event, owner: Bytes): void {
  let contract = safeContract(event);
  contract.safeOwners = withOwner(currentOwners(contract), owner);
  contract.save();
  recordOwner(event, logRowId(event), owner, true, false);
}

function removeOwner(event: ethereum.Event, owner: Bytes): void {
  let contract = safeContract(event);
  contract.safeOwners = withoutOwner(currentOwners(contract), owner);
  contract.save();
  recordOwner(event, logRowId(event), owner, false, false);
}

export function handleSafeAddedOwner(event: AddedOwner): void {
  addOwner(event, event.params.owner);
}

export function handleSafeRemovedOwner(event: RemovedOwner): void {
  removeOwner(event, event.params.owner);
}

/** Safe 1.3.0 emits the owner unindexed; the Base Safe ran on 1.3.0 before 1.4.1. */
export function handleSafe130AddedOwner(event: AddedOwner130): void {
  addOwner(event, event.params.owner);
}

export function handleSafe130RemovedOwner(event: RemovedOwner130): void {
  removeOwner(event, event.params.owner);
}

export function handleSafeChangedThreshold(event: ChangedThreshold): void {
  recordThreshold(event, event.params.threshold, false);
}
