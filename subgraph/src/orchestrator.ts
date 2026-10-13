import {
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
} from "../generated/templates/Orchestrator/AccessControl";
import { recordRoleAdminChange, recordRoleGrant } from "./lib/accesscontrol";
import { ContractKind } from "./lib/contract";

export function handleOrchestratorRoleGranted(event: RoleGranted): void {
  recordRoleGrant(
    ContractKind.ORCHESTRATOR,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    true,
  );
}

export function handleOrchestratorRoleRevoked(event: RoleRevoked): void {
  recordRoleGrant(
    ContractKind.ORCHESTRATOR,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    false,
  );
}

export function handleOrchestratorRoleAdminChanged(
  event: RoleAdminChanged,
): void {
  recordRoleAdminChange(
    ContractKind.ORCHESTRATOR,
    event,
    event.params.role,
    event.params.previousAdminRole,
    event.params.newAdminRole,
  );
}
