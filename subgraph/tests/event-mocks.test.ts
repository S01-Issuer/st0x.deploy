import { newMockEvent } from "matchstick-as";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

/**
 * Shared mock-log builders. Every builder takes the emitting contract, the
 * event's own params, a block number and a log index, and returns a bare
 * `ethereum.Event` for the caller to `changetype` into the generated class its
 * handler expects — `graph codegen` emits a separate class per (data source,
 * ABI) pair, so there is no one type these could return.
 *
 * Block number and log index are always explicit because the recorders stamp
 * every history row with the block and key it on transaction hash ++ log index:
 * two logs left on matchstick's defaults would collapse onto the same row and
 * hide exactly the bugs these tests are for.
 */

/** The transaction every mock log here is emitted from. */
export const TX_HASH: Bytes = Bytes.fromHexString(
  "0xdeadbeef00000000000000000000000000000000000000000000000000000001",
);

/** The EOA that submitted that transaction — `RoleGrant.transactionFrom`. */
export const TX_FROM: Address = Address.fromString(
  "0x00000000000000000000000000000000000000ff",
);

function mockLog(
  contract: Address,
  blockNumber: i32,
  logIndex: i32,
  params: Array<ethereum.EventParam>,
): ethereum.Event {
  let event = newMockEvent();
  event.address = contract;
  event.logIndex = BigInt.fromI32(logIndex);
  event.block.number = BigInt.fromI32(blockNumber);
  event.block.timestamp = BigInt.fromI32(blockNumber * 12);
  event.transaction.hash = TX_HASH;
  event.transaction.from = TX_FROM;
  event.parameters = params;
  return event;
}

/**
 * `RoleGranted(bytes32,address,address)` or `RoleRevoked(bytes32,address,address)`
 * — the two carry the same three params, and which one it is is decided by the
 * handler the caller hands it to.
 */
export function roleChangeLog(
  contract: Address,
  role: Bytes,
  account: Address,
  sender: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)),
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account)),
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
  ]);
}

/** `RoleAdminChanged(bytes32,bytes32,bytes32)`. */
export function roleAdminChangedLog(
  contract: Address,
  role: Bytes,
  previousAdminRole: Bytes,
  newAdminRole: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)),
    new ethereum.EventParam(
      "previousAdminRole",
      ethereum.Value.fromFixedBytes(previousAdminRole),
    ),
    new ethereum.EventParam(
      "newAdminRole",
      ethereum.Value.fromFixedBytes(newAdminRole),
    ),
  ]);
}

/** `OwnershipTransferred(address,address)`. */
export function ownershipTransferredLog(
  contract: Address,
  previousOwner: Address,
  newOwner: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam(
      "previousOwner",
      ethereum.Value.fromAddress(previousOwner),
    ),
    new ethereum.EventParam("newOwner", ethereum.Value.fromAddress(newOwner)),
  ]);
}

/** `Upgraded(address)`, as emitted by an `UpgradeableBeacon`. */
export function upgradedLog(
  contract: Address,
  implementation: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam(
      "implementation",
      ethereum.Value.fromAddress(implementation),
    ),
  ]);
}

/** `Deployment(address,address,address)` from the receipt vault deployer. */
export function receiptVaultDeploymentLog(
  deployer: Address,
  sender: Address,
  offchainAssetReceiptVault: Address,
  receipt: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(deployer, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam(
      "offchainAssetReceiptVault",
      ethereum.Value.fromAddress(offchainAssetReceiptVault),
    ),
    new ethereum.EventParam("receipt", ethereum.Value.fromAddress(receipt)),
  ]);
}

/** `Deployment(address,address,address)` from the orchestrator deployer. */
export function orchestratorDeploymentLog(
  deployer: Address,
  sender: Address,
  orchestrator: Address,
  owner: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(deployer, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam(
      "orchestrator",
      ethereum.Value.fromAddress(orchestrator),
    ),
    new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)),
  ]);
}
