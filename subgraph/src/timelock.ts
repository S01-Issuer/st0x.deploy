import {
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
} from "../generated/GovernanceTimelock/AccessControl";
import { recordRoleAdminChange, recordRoleGrant } from "./lib/accesscontrol";
import { ContractKind } from "./lib/contract";

export function handleTimelockRoleGranted(event: RoleGranted): void {
  recordRoleGrant(
    ContractKind.GOVERNANCE_TIMELOCK,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    true,
  );
}

export function handleTimelockRoleRevoked(event: RoleRevoked): void {
  recordRoleGrant(
    ContractKind.GOVERNANCE_TIMELOCK,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    false,
  );
}

export function handleTimelockRoleAdminChanged(event: RoleAdminChanged): void {
  recordRoleAdminChange(
    ContractKind.GOVERNANCE_TIMELOCK,
    event,
    event.params.role,
    event.params.previousAdminRole,
    event.params.newAdminRole,
  );
}
