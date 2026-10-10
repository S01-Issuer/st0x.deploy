import { Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  Contract,
  Role,
  RoleAdminChange,
  RoleGrant,
  RoleHolder,
} from "../../generated/schema";
import { getOrCreateContract } from "./contract";
import { logRowId } from "./event";

/**
 * `DEFAULT_ADMIN_ROLE`. OpenZeppelin's `AccessControl` administers every role
 * with this one until `_setRoleAdmin` moves it, and emits nothing to say so,
 * which makes it the only correct seed for a fresh `Role.admin`.
 */
function defaultAdminRole(): Bytes {
  return Bytes.fromHexString(
    "0x0000000000000000000000000000000000000000000000000000000000000000",
  );
}

/** `Role.id`: the contract address followed by the raw `bytes32` role. */
export function roleId(contract: Bytes, role: Bytes): Bytes {
  return contract.concat(role);
}

/** `RoleHolder.id`: the `Role.id` followed by the account. */
export function roleHolderId(
  contract: Bytes,
  role: Bytes,
  account: Bytes,
): Bytes {
  return roleId(contract, role).concat(account);
}

function getOrCreateRole(contract: Contract, role: Bytes): Role {
  let id = roleId(contract.id, role);
  let existing = Role.load(id);
  if (existing !== null) {
    return existing;
  }
  let entity = new Role(id);
  entity.contract = contract.id;
  entity.role = role;
  entity.admin = defaultAdminRole();
  entity.holderCount = 0;
  entity.save();
  return entity;
}

function getOrNewRoleHolder(id: Bytes, role: Bytes, account: Bytes): RoleHolder {
  let existing = RoleHolder.load(id);
  if (existing !== null) {
    return existing;
  }
  let holder = new RoleHolder(id);
  holder.role = role;
  holder.account = account;
  holder.held = false;
  return holder;
}

/**
 * Record one `RoleGranted` (`granted` true) or `RoleRevoked` (false).
 *
 * `holderCount` moves only when `RoleHolder.held` actually flips. OpenZeppelin
 * emits nothing for a grant to an account that already holds the role or a
 * revoke from one that does not, so a repeat of either log can only reach us as
 * a replay of the same log, and counting it would skew the count permanently.
 */
export function recordRoleGrant(
  kind: string,
  event: ethereum.Event,
  role: Bytes,
  account: Bytes,
  sender: Bytes,
  granted: boolean,
): void {
  let contract = getOrCreateContract(event.address, kind, event.block.number);
  let roleEntity = getOrCreateRole(contract, role);

  let holder = getOrNewRoleHolder(
    roleHolderId(contract.id, role, account),
    roleEntity.id,
    account,
  );
  if (holder.held != granted) {
    roleEntity.holderCount = granted
      ? roleEntity.holderCount + 1
      : roleEntity.holderCount - 1;
    roleEntity.save();
  }
  holder.held = granted;
  if (granted) {
    holder.grantedAtBlock = event.block.number;
    holder.grantedAtTimestamp = event.block.timestamp;
  } else {
    holder.revokedAtBlock = event.block.number;
    holder.revokedAtTimestamp = event.block.timestamp;
  }
  holder.save();

  let row = new RoleGrant(logRowId(event));
  row.role = roleEntity.id;
  row.account = account;
  row.granted = granted;
  row.sender = sender;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

/**
 * Record one `RoleAdminChanged` log and move the role's current admin.
 *
 * `_setRoleAdmin` is the only writer of that mapping and always emits, so the
 * log is the whole truth and `previousAdminRole` is taken from it rather than
 * read back off the `Role` row.
 */
export function recordRoleAdminChange(
  kind: string,
  event: ethereum.Event,
  role: Bytes,
  previousAdminRole: Bytes,
  newAdminRole: Bytes,
): void {
  let contract = getOrCreateContract(event.address, kind, event.block.number);
  let roleEntity = getOrCreateRole(contract, role);
  roleEntity.admin = newAdminRole;
  roleEntity.save();

  let row = new RoleAdminChange(logRowId(event));
  row.role = roleEntity.id;
  row.previousAdminRole = previousAdminRole;
  row.newAdminRole = newAdminRole;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}
