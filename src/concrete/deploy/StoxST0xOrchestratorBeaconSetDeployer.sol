// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    ST0xOrchestratorBeaconSetDeployer,
    ST0xOrchestratorBeaconSetDeployerConfig
} from "./ST0xOrchestratorBeaconSetDeployer.sol";
import {LibProdDeployV4} from "../../lib/LibProdDeployV4.sol";

/// @title StoxST0xOrchestratorBeaconSetDeployer
/// @notice Zoltu-deployable ST0xOrchestratorBeaconSetDeployer with config
/// hardcoded from `LibProdDeployV4`. Mirrors the pattern used by
/// `StoxOffchainAssetReceiptVaultBeaconSetDeployer`: the base takes a config
/// struct in its constructor; this concrete subclass supplies the config
/// with hardcoded constants so its constructor takes no dynamic input and
/// the whole thing is deterministic.
contract StoxST0xOrchestratorBeaconSetDeployer is
    ST0xOrchestratorBeaconSetDeployer(ST0xOrchestratorBeaconSetDeployerConfig({
            initialOwner: LibProdDeployV4.BEACON_INITIAL_OWNER,
            initialOrchestratorImplementation: LibProdDeployV4.ST0X_ORCHESTRATOR_RAIN_VATS_0_1_6
        }))
{}
