import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  Deployment,
  OffchainAssetReceiptVaultBeaconSetDeployer,
} from "../generated/ReceiptVaultDeployer/OffchainAssetReceiptVaultBeaconSetDeployer";
import { UpgradeableBeacon } from "../generated/ReceiptVaultDeployer/UpgradeableBeacon";
import { ReceiptVault, VaultBeacon } from "../generated/templates";
import { ContractKind, createDiscoveredContract } from "./lib/contract";

/**
 * Index everything one `Deployment` from the beacon-set deployer brings into
 * view. The deployer is the discovery root because listing the vaults by
 * address is not viable — 54 production tokens a chain and growing.
 *
 * The vault needs no read. Its `OwnershipTransferred(0 -> initialAdmin)` fires
 * inside `initialize`, earlier in this very transaction, and graph-node
 * re-matches the whole creating block against a newly created template, so that
 * log reaches `handleReceiptVaultOwnershipTransferred` and the vault's
 * ownership history is complete from its first owner. Seeding the owner here as
 * well would write a second row for state that already has a log behind it.
 *
 * The two beacons are the opposite case: the deployer creates them in its own
 * constructor, in a block strictly before any `Deployment`, so their
 * construction-time `OwnershipTransferred` and `Upgraded` are outside the
 * template's range and can never be replayed into it. Current state has to be
 * read instead, and `createDiscoveredContract` marks it as read rather than
 * logged.
 */
export function handleReceiptVaultDeployment(event: Deployment): void {
  if (
    createDiscoveredContract(
      event.params.offchainAssetReceiptVault,
      ContractKind.RECEIPT_VAULT,
      event.block.number,
      null,
      null,
    )
  ) {
    ReceiptVault.create(event.params.offchainAssetReceiptVault);
  }

  let deployer = OffchainAssetReceiptVaultBeaconSetDeployer.bind(event.address);

  let vaultBeacon = receiptVaultBeacon(deployer);
  if (vaultBeacon != null) {
    indexBeacon(vaultBeacon, event.block.number);
  }

  let receipt = receiptBeacon(deployer);
  if (receipt != null) {
    indexBeacon(receipt, event.block.number);
  }
}

/**
 * The receipt vault beacon this deployer was constructed with, or null when
 * neither getter answers.
 *
 * The Base-generation deployer predates the `I_`-to-camelCase immutable
 * rename, so the committed ABI carries both spellings and only one of them
 * exists on any given chain. The camelCase name is the current one, so it is
 * tried first and the screaming-snake name is the fallback.
 */
function receiptVaultBeacon(
  deployer: OffchainAssetReceiptVaultBeaconSetDeployer,
): Address | null {
  let camelCase = deployer.try_iOffchainAssetReceiptVaultBeacon();
  if (!camelCase.reverted) {
    return camelCase.value;
  }
  let screamingSnake = deployer.try_I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON();
  if (!screamingSnake.reverted) {
    return screamingSnake.value;
  }
  return null;
}

/** The receipt beacon, resolved the same two ways as the vault beacon. */
function receiptBeacon(
  deployer: OffchainAssetReceiptVaultBeaconSetDeployer,
): Address | null {
  let camelCase = deployer.try_iReceiptBeacon();
  if (!camelCase.reverted) {
    return camelCase.value;
  }
  let screamingSnake = deployer.try_I_RECEIPT_BEACON();
  if (!screamingSnake.reverted) {
    return screamingSnake.value;
  }
  return null;
}

/**
 * Bring one constructor-created beacon into the index, reading its current
 * owner and implementation at this block because no log of either is reachable.
 * A getter that reverts leaves the field null rather than failing the handler:
 * a beacon whose ownership has been renounced to a non-`Ownable` successor
 * would otherwise stall the whole subgraph.
 *
 * `createDiscoveredContract` returning false means some earlier `Deployment`
 * already did this, and the template must not be created a second time.
 */
function indexBeacon(address: Address, block: BigInt): void {
  let beacon = UpgradeableBeacon.bind(address);

  let owner = beacon.try_owner();
  let ownerValue: Bytes | null = null;
  if (!owner.reverted) {
    ownerValue = owner.value;
  }

  let implementation = beacon.try_implementation();
  let implementationValue: Bytes | null = null;
  if (!implementation.reverted) {
    implementationValue = implementation.value;
  }

  if (
    createDiscoveredContract(
      address,
      ContractKind.BEACON,
      block,
      ownerValue,
      implementationValue,
    )
  ) {
    VaultBeacon.create(address);
  }
}
