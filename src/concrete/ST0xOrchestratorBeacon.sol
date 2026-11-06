// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../lib/LibStoxConfig.sol";

/// @title ST0xOrchestratorBeacon
/// @notice The `UpgradeableBeacon` behind the orchestrator's registry beacon
/// proxy, Zoltu-deployed. Implementation is `LibProdDeployCurrent.ST0X_ORCHESTRATOR`;
/// owner is the beacon initial owner bound in the `ConfigRegistry`, so the
/// creation code is chain-invariant and the deploy key never owns the beacon.
/// @dev Reverts until the root authority binds a nonzero
/// `LibStoxConfig.BEACON_INITIAL_OWNER_NAME`, and until the implementation has
/// code.
contract ST0xOrchestratorBeacon is
    UpgradeableBeacon(LibProdDeployCurrent.ST0X_ORCHESTRATOR, LibStoxConfig.beaconInitialOwner())
{}
