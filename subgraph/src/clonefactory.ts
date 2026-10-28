import { Address, BigInt, dataSource } from "@graphprotocol/graph-ts";
import { NewBeaconProxy } from "../generated/CloneFactoryV5/CloneFactoryV5";
import { NewRegistryBeaconProxy } from "../generated/CloneFactoryV6/CloneFactoryV6";
import { NewRegistryBeaconProxy as NewRegistryBeaconProxyV7 } from "../generated/CloneFactoryV7/CloneFactoryV7";
import { OffchainAssetReceiptVaultBeaconSetDeployer } from "../generated/CloneFactoryV6/OffchainAssetReceiptVaultBeaconSetDeployer";
import { Contract } from "../generated/schema";
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
/**
 * Index a vault a clone factory built over the chain's receipt-vault beacon,
 * recording the factory. Every clone factory is shared by every rain consumer,
 * so a proxy over any other beacon is not st0x's and is skipped.
 *
 * As for a deployer-built vault, the proxy's `OwnershipTransferred` fires inside
 * `initialize` earlier in this transaction and is replayed into the new
 * template, so nothing is read for it here.
 */
function discoverFactoryVault(
  factory: Address,
  beacon: Address,
  proxy: Address,
  block: BigInt,
): void {
  let expected = receiptVaultBeacon(dataSource.network());
  if (expected === null) {
    return;
  }
  if (!beacon.equals(expected)) {
    return;
  }
  if (
    createDiscoveredContract(
      proxy,
      ContractKind.RECEIPT_VAULT,
      block,
      null,
      null,
    )
  ) {
    let contract = Contract.load(proxy)!;
    contract.factory = factory;
    contract.save();
    ReceiptVault.create(proxy);
  }
}

/** `ICloneableFactoryV5.NewBeaconProxy`. */
export function handleCloneFactoryV5NewBeaconProxy(
  event: NewBeaconProxy,
): void {
  discoverFactoryVault(
    event.address,
    event.params.beacon,
    event.params.proxy,
    event.block.number,
  );
}

/**
 * `ICloneableFactoryV6.NewRegistryBeaconProxy`. The event carries the beacon the
 * binding resolved to, which is the one the proxy keeps.
 */
export function handleCloneFactoryV6NewRegistryBeaconProxy(
  event: NewRegistryBeaconProxy,
): void {
  discoverFactoryVault(
    event.address,
    event.params.beacon,
    event.params.proxy,
    event.block.number,
  );
}

/** `ICloneableFactoryV7.NewRegistryBeaconProxy`, the same event. */
export function handleCloneFactoryV7NewRegistryBeaconProxy(
  event: NewRegistryBeaconProxyV7,
): void {
  discoverFactoryVault(
    event.address,
    event.params.beacon,
    event.params.proxy,
    event.block.number,
  );
}
