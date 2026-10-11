// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title IST0xOrchestratorBeaconSetDeployerV2
/// @notice V2 interface for the ST0xOrchestratorBeaconSetDeployer — advertised
/// via ERC-165 so a consumer holding a deployer address can confirm it is an
/// ST0x orchestrator beacon-set deployer. Supersedes
/// `IST0xOrchestratorBeaconSetDeployerV1`: `deploy` takes no owner.
interface IST0xOrchestratorBeaconSetDeployerV2 {
    /// Emitted when an `ST0xOrchestrator` singleton is deployed.
    /// @dev `deploy` is permissionless, so anyone can emit this event, but
    /// never with an owner of their choosing: every instance is initialised
    /// with the owner the address registry resolves, so instances from this
    /// deployer differ only in address and state.
    /// @param sender The address that called `deploy`.
    /// @param orchestrator Address of the newly deployed orchestrator proxy.
    /// @param owner The address granted `DEFAULT_ADMIN_ROLE`, as resolved from
    /// the address registry.
    event Deployment(address indexed sender, address indexed orchestrator, address owner);

    /// @notice Deploy an `ST0xOrchestrator` singleton. The owner is resolved
    /// from the address registry by `initialize`, not supplied by the caller.
    /// The resolved owner appears on `Deployment`.
    /// @return The address of the deployed orchestrator `BeaconProxy`.
    function deploy() external returns (address);
}
