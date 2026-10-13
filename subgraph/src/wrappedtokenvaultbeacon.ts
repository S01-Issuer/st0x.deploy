import {
  OwnershipTransferred,
  Upgraded,
} from "../generated/WrappedTokenVaultBeacon/UpgradeableBeacon";
import {
  ContractKind,
  recordBeaconUpgrade,
  recordOwnershipTransfer,
} from "./lib/contract";

export function handleWrappedTokenVaultBeaconOwnershipTransferred(
  event: OwnershipTransferred,
): void {
  recordOwnershipTransfer(
    ContractKind.BEACON,
    event,
    event.params.previousOwner,
    event.params.newOwner,
  );
}

export function handleWrappedTokenVaultBeaconUpgraded(event: Upgraded): void {
  recordBeaconUpgrade(ContractKind.BEACON, event, event.params.implementation);
}
