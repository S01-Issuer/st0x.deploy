import { Address, dataSource } from "@graphprotocol/graph-ts";
import { NewRegistryBeaconProxy } from "../generated/CloneFactory/CloneFactory";
import { OffchainAssetReceiptVaultBeaconSetDeployer } from "../generated/CloneFactory/OffchainAssetReceiptVaultBeaconSetDeployer";
import { ReceiptVault } from "../generated/templates";
import { ContractKind, createDiscoveredContract } from "./lib/contract";

/** st0x `LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1`: Base's receipt-vault beacon. */
export const BASE_RECEIPT_VAULT_BEACON =
  "0xEa084c8F4331CDF3328E772781b59F8A24F28F1A";

/**
 * st0x `LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1`,
 * whose `iOffchainAssetReceiptVaultBeacon()` is the receipt-vault beacon on
 * every chain that bootstrapped at 0.1.1.
 */
export const RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1 =
  "0xd64246e6b25F745f005E6233e050C9B879E660Dc";

/**
 * The chain's receipt-vault beacon, resolved as st0x
 * `LibBeaconInvariants.prodBeaconsForChainId` resolves it: Base's V1 constant,
 * the 0.1.1 deployer's getter on the 0.1.1 chains. Null for any other network,
 * or when the getter reverts.
 */
export function receiptVaultBeacon(network: string): Address | null {
  if (network == "base") {
    return Address.fromString(BASE_RECEIPT_VAULT_BEACON);
  }
  if (
    network == "mainnet" ||
    network == "hyperevm" ||
    network == "robinhood" ||
    network == "bsc"
  ) {
    let beacon = OffchainAssetReceiptVaultBeaconSetDeployer.bind(
      Address.fromString(RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1),
    ).try_iOffchainAssetReceiptVaultBeacon();
    if (!beacon.reverted) {
      return beacon.value;
    }
  }
  return null;
}

/**
 * Index a vault the V6 clone factory built as a registry beacon proxy over the
 * chain's receipt-vault beacon. The factory is shared by every rain consumer,
 * so a proxy over any other beacon is not st0x's and is skipped. The event
 * carries the beacon the binding resolved to, which is the one the proxy keeps.
 *
 * As for a deployer-built vault, the proxy's `OwnershipTransferred` fires inside
 * `initialize` earlier in this transaction and is replayed into the new
 * template, so nothing is read for it here.
 */
export function handleCloneFactoryNewRegistryBeaconProxy(
  event: NewRegistryBeaconProxy,
): void {
  let beacon = receiptVaultBeacon(dataSource.network());
  if (beacon === null) {
    return;
  }
  if (!event.params.beacon.equals(beacon)) {
    return;
  }
  if (
    createDiscoveredContract(
      event.params.proxy,
      ContractKind.RECEIPT_VAULT,
      event.block.number,
      null,
      null,
    )
  ) {
    ReceiptVault.create(event.params.proxy);
  }
}
