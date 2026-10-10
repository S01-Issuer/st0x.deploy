import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  BeaconUpgrade,
  Contract,
  OwnershipTransfer,
} from "../../generated/schema";
import { logRowId } from "./event";

/**
 * The values of the schema's `ContractKind` enum. `graph codegen` renders an
 * enum field as a plain `string` and generates nothing for the enum itself, so
 * the valid values have to be written out somewhere; a typo here reaches the
 * store as an unknown enum value and fails the query, not the build.
 */
export namespace ContractKind {
  export const AUTHORIZER = "AUTHORIZER";
  export const GOVERNANCE_TIMELOCK = "GOVERNANCE_TIMELOCK";
  export const ORCHESTRATOR = "ORCHESTRATOR";
  export const BEACON = "BEACON";
  export const RECEIPT_VAULT = "RECEIPT_VAULT";
}

/**
 * The `Contract` row for `address`, created on first sight with `block` as its
 * `firstIndexedBlock`. That field is only ever written at creation: it is the
 * lower bound of the history the row carries, and moving it forward would
 * claim history the subgraph does in fact hold is missing.
 */
export function getOrCreateContract(
  address: Bytes,
  kind: string,
  block: BigInt,
): Contract {
  let existing = Contract.load(address);
  if (existing !== null) {
    return existing;
  }
  let contract = new Contract(address);
  contract.kind = kind;
  contract.firstIndexedBlock = block;
  contract.ownerFromLog = false;
  contract.implementationFromLog = false;
  contract.templateCreated = false;
  contract.save();
  return contract;
}

/**
 * Create the `Contract` row for a contract this subgraph found by discovery
 * rather than by one of its own logs, carrying whatever current state the
 * caller was able to read at the discovery block. `ownerFromLog` and
 * `implementationFromLog` stay false, so a consumer can tell a value read at
 * discovery from one a log established.
 *
 * Returns whether the caller should create this contract's data source
 * template, and records that it is about to. False means a template already
 * exists, so creating a second one would index the same contract twice.
 *
 * A row already existing is not that question. It also happens when one of the
 * contract's own logs reached a static data source first, and then no template
 * was ever created — answering false there would leave the contract indexed but
 * unwatched, with nothing listening for its later logs. `templateCreated` is
 * what separates the two, and the existing row's read state is left alone
 * because a log is a better source than a call at discovery.
 */
export function createDiscoveredContract(
  address: Bytes,
  kind: string,
  block: BigInt,
  owner: Bytes | null,
  implementation: Bytes | null,
): boolean {
  let existing = Contract.load(address);
  if (existing !== null) {
    if (existing.templateCreated) {
      return false;
    }
    existing.templateCreated = true;
    existing.save();
    return true;
  }
  let contract = new Contract(address);
  contract.kind = kind;
  contract.firstIndexedBlock = block;
  contract.ownerFromLog = false;
  contract.implementationFromLog = false;
  contract.templateCreated = true;
  if (owner !== null) {
    contract.owner = owner;
    contract.ownerAsOfBlock = block;
  }
  if (implementation !== null) {
    contract.implementation = implementation;
    contract.implementationAsOfBlock = block;
  }
  contract.save();
  return true;
}

/**
 * Record one `OwnershipTransferred` log and move the contract's current owner
 * to the new one. A log always wins over a value read at discovery, which is
 * what `ownerFromLog` going true records.
 */
export function recordOwnershipTransfer(
  kind: string,
  event: ethereum.Event,
  previousOwner: Bytes,
  newOwner: Bytes,
): void {
  let contract = getOrCreateContract(event.address, kind, event.block.number);
  contract.owner = newOwner;
  contract.ownerAsOfBlock = event.block.number;
  contract.ownerFromLog = true;
  contract.save();

  let row = new OwnershipTransfer(logRowId(event));
  row.contract = contract.id;
  row.previousOwner = previousOwner;
  row.newOwner = newOwner;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

/**
 * Record one beacon `Upgraded` log and move the beacon's current
 * implementation. Only an `UpgradeableBeacon` emits this; a `BeaconProxy`
 * emits `BeaconUpgraded`, which is a different event and not indexed here.
 */
export function recordBeaconUpgrade(
  kind: string,
  event: ethereum.Event,
  implementation: Bytes,
): void {
  let contract = getOrCreateContract(event.address, kind, event.block.number);
  contract.implementation = implementation;
  contract.implementationAsOfBlock = event.block.number;
  contract.implementationFromLog = true;
  contract.save();

  let row = new BeaconUpgrade(logRowId(event));
  row.contract = contract.id;
  row.implementation = implementation;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}
