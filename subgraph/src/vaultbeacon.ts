import {
  OwnershipTransferred,
  Upgraded,
} from "../generated/templates/VaultBeacon/UpgradeableBeacon";
import {
  ContractKind,
  recordBeaconUpgrade,
  recordOwnershipTransfer,
} from "./lib/contract";

export function handleVaultBeaconOwnershipTransferred(
  event: OwnershipTransferred,
): void {
  recordOwnershipTransfer(
    ContractKind.BEACON,
    event,
    event.params.previousOwner,
    event.params.newOwner,
  );
}

export function handleVaultBeaconUpgraded(event: Upgraded): void {
  recordBeaconUpgrade(ContractKind.BEACON, event, event.params.implementation);
}
