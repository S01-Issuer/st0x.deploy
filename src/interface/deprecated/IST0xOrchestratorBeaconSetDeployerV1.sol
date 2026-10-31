// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title IST0xOrchestratorBeaconSetDeployerV1
/// @notice V1 interface for the ST0xOrchestratorBeaconSetDeployer — advertised
/// via ERC-165 so a consumer holding a deployer address can confirm it is an
/// ST0x orchestrator beacon-set deployer.
interface IST0xOrchestratorBeaconSetDeployerV1 {
    /// Emitted when an `ST0xOrchestrator` singleton is deployed.
    /// @dev `deploy` is permissionless, so anyone can emit this event with
    /// any owner. Consumers MUST filter on the expected `owner` (and ideally
    /// take the address from their own deploy transaction rather than event
    /// discovery) — an attacker can front-run a lookalike that differs only
    /// in who holds `DEFAULT_ADMIN_ROLE`.
    /// @param sender The address that called `deploy`.
    /// @param orchestrator Address of the newly deployed orchestrator proxy.
    /// @param owner The address granted `DEFAULT_ADMIN_ROLE`.
    event Deployment(address indexed sender, address indexed orchestrator, address owner);

    /// @notice Deploy an `ST0xOrchestrator` singleton owned by `owner`.
    /// @param owner The address granted `DEFAULT_ADMIN_ROLE` on the deployed
    /// orchestrator.
    /// @return The address of the deployed orchestrator `BeaconProxy`.
    function deploy(address owner) external returns (address);
}
