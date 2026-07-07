// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @title IST0xOrchestratorBeaconSetDeployerV1
/// @notice V1 interface for the ST0xOrchestratorBeaconSetDeployer — advertised
/// via ERC-165 so a consumer holding a deployer address can confirm it is an
/// ST0x orchestrator beacon-set deployer.
interface IST0xOrchestratorBeaconSetDeployerV1 {
    /// @notice Deploy an `ST0xOrchestrator` singleton owned by `owner`.
    /// @param owner The address granted `DEFAULT_ADMIN_ROLE` on the deployed
    /// orchestrator.
    /// @return The address of the deployed orchestrator `BeaconProxy`.
    function deploy(address owner) external returns (address);
}
