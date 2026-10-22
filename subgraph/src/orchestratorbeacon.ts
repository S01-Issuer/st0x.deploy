import {
  OwnershipTransferred,
  Upgraded,
} from "../generated/OrchestratorBeacon/UpgradeableBeacon";
import {
  ContractKind,
  recordBeaconUpgrade,
  recordOwnershipTransfer,
} from "./lib/contract";

export function handleOrchestratorBeaconOwnershipTransferred(
  event: OwnershipTransferred,
): void {
  recordOwnershipTransfer(
    ContractKind.BEACON,
    event,
    event.params.previousOwner,
    event.params.newOwner,
  );
}

export function handleOrchestratorBeaconUpgraded(event: Upgraded): void {
  recordBeaconUpgrade(ContractKind.BEACON, event, event.params.implementation);
}
