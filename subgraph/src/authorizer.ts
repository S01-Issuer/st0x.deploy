import {
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
} from "../generated/Authorizer/AccessControl";
import { recordRoleAdminChange, recordRoleGrant } from "./lib/accesscontrol";
import { ContractKind } from "./lib/contract";

// Thin per-data-source entry points: `graph codegen` emits a distinct event
// class per (data source, ABI) pair and AssemblyScript has no structural
// typing, so the same handler body cannot be shared across data sources. These
// pass the event and its params straight to the recorders.

export function handleAuthorizerRoleGranted(event: RoleGranted): void {
  recordRoleGrant(
    ContractKind.AUTHORIZER,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    true,
  );
}

export function handleAuthorizerRoleRevoked(event: RoleRevoked): void {
  recordRoleGrant(
    ContractKind.AUTHORIZER,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    false,
  );
}

export function handleAuthorizerRoleAdminChanged(
  event: RoleAdminChanged,
): void {
  recordRoleAdminChange(
    ContractKind.AUTHORIZER,
    event,
    event.params.role,
    event.params.previousAdminRole,
    event.params.newAdminRole,
  );
}
