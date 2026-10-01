// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibProdBeaconsBase} from "../../../../src/lib/LibProdBeaconsBase.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";

/// @title BaseBeaconOwnershipTest
/// @notice Base's leg of the per-chain beacon pin.
/// @dev Unpinned Base head fork: drift detection against live state.
contract BaseBeaconOwnershipTest is Test {
    /// @notice Base's three in-use token beacons carry the OZ
    /// `UpgradeableBeacon` codehash, are owned by Base's token-owner Safe,
    /// and point at the pinned implementations: the wrapped-token-vault
    /// beacon serves the 0.1.1 impl, the receipt and receipt-vault beacons
    /// serve 0.1.30. Base's beacon addresses are the V1-generation ones.
    ///
    /// The orchestrator beacon is out of scope: its owner is asserted by
    /// `assertProdBeaconsOwnedByChainSafe` and its build by
    /// `LibOrchestratorInvariants`.
    function testBaseBeaconsAreSafeOwnedAtTheirPinnedImpls() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

        vm.createSelectFork(LibRainDeploy.BASE);
        address[4] memory beacons = LibProdBeaconsBase.beacons();
        address[4] memory impls = LibProdBeaconsBase.implementations();
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
            safe,
            impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], safe, LibProdDeployV4.STOX_RECEIPT_0_1_30
        );
        LibBeaconInvariants.assertBeaconInvariants(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], safe, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30
        );
    }
}
