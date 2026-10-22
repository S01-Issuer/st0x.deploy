import { Bytes } from "@graphprotocol/graph-ts";
import {
  Approved,
  Register,
  Revoked,
} from "../generated/ConfigRegistry/ConfigRegistry";
import { ConfigBinding, ConfigRegister } from "../generated/schema";
import { ContractKind, getOrCreateContract } from "./lib/contract";
import { logRowId } from "./lib/event";
import { recordDelegateChange } from "./lib/registry";

/** `ConfigBinding.id`: registry ++ authority ++ the `bytes32` name. */
export function configBindingId(
  registry: Bytes,
  authority: Bytes,
  name: Bytes,
): Bytes {
  return registry.concat(authority).concat(name);
}

/**
 * Record one `Register` and move the binding to its value. The most recent
 * `Register` for an (authority, name) is the binding `getV3` answers, so the
 * log is the whole truth.
 */
export function handleConfigRegistryRegister(event: Register): void {
  let rowId = logRowId(event);
  let registry = getOrCreateContract(
    event.address,
    ContractKind.CONFIG_REGISTRY,
    event.block.number,
  );
  let id = configBindingId(
    registry.id,
    event.params.authority,
    event.params.name,
  );
  let binding = ConfigBinding.load(id);
  if (binding === null) {
    binding = new ConfigBinding(id);
    binding.registry = registry.id;
    binding.authority = event.params.authority;
    binding.name = event.params.name;
    binding.registerCount = 0;
  }
  binding.value = event.params.value;
  binding.sender = event.params.sender;
  binding.boundAtBlock = event.block.number;
  binding.boundAtTimestamp = event.block.timestamp;
  binding.registerCount = binding.registerCount + 1;
  binding.save();

  let row = new ConfigRegister(rowId);
  row.binding = id;
  row.sender = event.params.sender;
  row.value = event.params.value;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

export function handleConfigRegistryApproved(event: Approved): void {
  recordDelegateChange(
    ContractKind.CONFIG_REGISTRY,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleConfigRegistryRevoked(event: Revoked): void {
  recordDelegateChange(
    ContractKind.CONFIG_REGISTRY,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    false,
  );
}
