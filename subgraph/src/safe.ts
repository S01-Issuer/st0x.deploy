import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  AddedOwner,
  ChangedThreshold,
  RemovedOwner,
  SafeSetup,
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
  contract.threshold = threshold;
  contract.thresholdAsOfBlock = event.block.number;
  contract.save();

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
  contract.safeOwners = owners;
  contract.save();
  recordThreshold(event, event.params.threshold, true);
}

export function handleSafeAddedOwner(event: AddedOwner): void {
  let contract = safeContract(event);
  let owners = currentOwners(contract);
  owners.push(event.params.owner);
  contract.safeOwners = owners;
  contract.save();
  recordOwner(event, logRowId(event), event.params.owner, true, false);
}

export function handleSafeRemovedOwner(event: RemovedOwner): void {
  let contract = safeContract(event);
  let owners = currentOwners(contract);
  let kept = new Array<Bytes>();
  for (let i = 0; i < owners.length; i++) {
    if (!owners[i].equals(event.params.owner)) kept.push(owners[i]);
  }
  contract.safeOwners = kept;
  contract.save();
  recordOwner(event, logRowId(event), event.params.owner, false, false);
}

export function handleSafeChangedThreshold(event: ChangedThreshold): void {
  recordThreshold(event, event.params.threshold, false);
}
