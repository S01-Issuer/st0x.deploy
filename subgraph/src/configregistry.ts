import { Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  Approved,
  Register,
  Revoked,
} from "../generated/ConfigRegistry/ConfigRegistry";
import {
  Approved as ApprovedV4,
  ConfigRegistryV4,
  MetaV1_2,
  Register as RegisterV4,
  Revoked as RevokedV4,
} from "../generated/ConfigRegistryV4/ConfigRegistryV4";
import { ConfigBinding, ConfigRegister } from "../generated/schema";
import { ContractKind, getOrCreateContract } from "./lib/contract";
import { logRowId } from "./lib/event";
import {
  addressWord,
  recordDelegateChange,
  recordRegistryMeta,
  recordMetaSubjectBinding,
  registryMetaSubject,
} from "./lib/registry";

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
 * `Register` for an (authority, name) is the binding `getV2` / `getV4` answers,
 * so the log is the whole truth. `registerCount` moves only for a log not seen
 * before: a replay of the same log rewrites the same `ConfigRegister` row and
 * must not count twice. Returns null for a replay.
 */
function recordRegister(
  kind: string,
  event: ethereum.Event,
  sender: Bytes,
  authority: Bytes,
  name: Bytes,
  value: Bytes,
  valueType: string | null,
  valueTypeHash: Bytes | null,
): ConfigRegister | null {
  let rowId = logRowId(event);
  if (ConfigRegister.load(rowId) !== null) {
    return null;
  }
  let registry = getOrCreateContract(event.address, kind, event.block.number);
  let id = configBindingId(registry.id, authority, name);
  let binding = ConfigBinding.load(id);
  if (binding === null) {
    binding = new ConfigBinding(id);
    binding.registry = registry.id;
    binding.authority = authority;
    binding.name = name;
    binding.registerCount = 0;
  }
  binding.value = value;
  binding.valueType = valueType;
  binding.valueTypeHash = valueTypeHash;
  binding.sender = sender;
  binding.boundAtBlock = event.block.number;
  binding.boundAtTimestamp = event.block.timestamp;
  binding.registerCount = binding.registerCount + 1;
  binding.save();

  let row = new ConfigRegister(rowId);
  row.binding = id;
  row.sender = sender;
  row.value = value;
  row.valueType = valueType;
  row.valueTypeHash = valueTypeHash;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
  return row;
}

export function handleConfigRegistryRegister(event: Register): void {
  recordRegister(
    ContractKind.CONFIG_REGISTRY,
    event,
    event.params.sender,
    event.params.authority,
    event.params.name,
    event.params.value,
    null,
    null,
  );
}

/**
 * The `IConfigRegistryV4` `MetaV1_2` subject for a binding:
 * `keccak256(abi.encode(authority, name))`.
 */
export function configMetaSubject(authority: Bytes, name: Bytes): Bytes {
  return registryMetaSubject(addressWord(authority).concat(name));
}

/**
 * A V4 `Register`. The type hash is the one `getV4` answers at the log's
 * block, not a hash of the decoded string: the event's `string` reaches the
 * mapping decoded, and an emitted type that is not valid UTF-8 would not
 * re-encode to the bytes the registry hashed. A name is bound at most once
 * per block (`TimestampNotAfterBinding`), so the block's closing state is
 * this log's binding.
 */
export function handleConfigRegistryV4Register(event: RegisterV4): void {
  let authority = event.params.authority;
  let name = event.params.name;
  let read = ConfigRegistryV4.bind(event.address).try_getV4(authority, name);
  let valueTypeHash: Bytes | null = null;
  if (!read.reverted) {
    valueTypeHash = read.value.value2;
  }
  let row = recordRegister(
    ContractKind.CONFIG_REGISTRY_V4,
    event,
    event.params.sender,
    authority,
    name,
    event.params.value,
    event.params.valueType,
    valueTypeHash,
  );
  if (row === null) {
    return;
  }
  let subject = configMetaSubject(authority, name);
  let binding = ConfigBinding.load(row.binding)!;
  binding.metaSubject = subject;
  binding.save();
  recordMetaSubjectBinding(event.address, subject, row.binding, row.id);
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

export function handleConfigRegistryV4Approved(event: ApprovedV4): void {
  recordDelegateChange(
    ContractKind.CONFIG_REGISTRY_V4,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleConfigRegistryV4Revoked(event: RevokedV4): void {
  recordDelegateChange(
    ContractKind.CONFIG_REGISTRY_V4,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    false,
  );
}

export function handleConfigRegistryV4MetaV1_2(event: MetaV1_2): void {
  recordRegistryMeta(
    ContractKind.CONFIG_REGISTRY_V4,
    event,
    event.params.sender,
    event.params.subject,
    event.params.meta,
  );
}
