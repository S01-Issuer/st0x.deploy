import {
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
} from "../generated/EuAuthorizer/AccessControl";
import { recordRoleAdminChange, recordRoleGrant } from "./lib/accesscontrol";
import { ContractKind } from "./lib/contract";

export function handleEuAuthorizerRoleGranted(event: RoleGranted): void {
  recordRoleGrant(
    ContractKind.AUTHORIZER,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    true,
  );
}

export function handleEuAuthorizerRoleRevoked(event: RoleRevoked): void {
  recordRoleGrant(
    ContractKind.AUTHORIZER,
    event,
    event.params.role,
    event.params.account,
    event.params.sender,
    false,
  );
}

export function handleEuAuthorizerRoleAdminChanged(
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
