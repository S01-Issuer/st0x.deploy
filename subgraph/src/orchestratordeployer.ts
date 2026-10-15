import { Deployment } from "../generated/OrchestratorDeployer/ST0xOrchestratorBeaconSetDeployer";
import { Orchestrator } from "../generated/templates";
import { ContractKind, createDiscoveredContract } from "./lib/contract";

/**
 * Index an orchestrator the moment its deployer announces it. `deploy` is
 * permissionless, so this picks up lookalikes alongside the production
 * orchestrator; telling them apart by `DEFAULT_ADMIN_ROLE` holder is exactly
 * what indexing them is for.
 *
 * Nothing is seeded from the event's `owner` param. The orchestrator's
 * `RoleGranted(DEFAULT_ADMIN_ROLE, owner)` is emitted from `initialize` in this
 * same transaction, and graph-node re-matches the creating block against the
 * new template, so the grant arrives through `handleOrchestratorRoleGranted`
 * with its real log behind it. Writing it here too would invent a `RoleGrant`
 * row for a log that was already indexed.
 */
export function handleOrchestratorDeployment(event: Deployment): void {
  if (
    createDiscoveredContract(
      event.params.orchestrator,
      ContractKind.ORCHESTRATOR,
      event.block.number,
      null,
      null,
    )
  ) {
    Orchestrator.create(event.params.orchestrator);
  }
}
