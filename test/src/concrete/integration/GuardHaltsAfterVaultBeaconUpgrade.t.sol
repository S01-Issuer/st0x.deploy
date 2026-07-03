// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";

import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {IST0xOrchestratorV1, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {IST0xVaultBeaconSet} from "../../../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../../../../src/lib/LibProdDeployV4.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title GuardHaltsAfterVaultBeaconUpgradeTest
/// @notice Workflow: upgrading the OARV vault beacon to a different
/// implementation, as the beacon owner, breaks the orchestrator's version
/// lock: `vaultLogicIsExpected` flips false and both `mint` and `burn`
/// revert `VaultLogicMismatch`.
contract GuardHaltsAfterVaultBeaconUpgradeTest is OrchestratorIntegrationTest {
    function testGuardHaltsAfterVaultBeaconUpgrade() external {
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard passes before the upgrade");

        IBeacon vaultBeacon = IST0xVaultBeaconSet(
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).iOffchainAssetReceiptVaultBeacon();

        // A fresh, valid impl address (any contract with code works as an
        // UpgradeableBeacon target) that is NOT the pinned V4 vault impl.
        address newImpl = address(new ST0xOrchestrator());
        vm.prank(BEACON_OWNER);
        UpgradeableBeacon(address(vaultBeacon)).upgradeTo(newImpl);

        assertFalse(orchestrator.vaultLogicIsExpected(), "guard halts after the vault beacon upgrade");

        (address eoa, uint256 pk) = makeAddrAndKey("halt-recipient");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, 1e18, keccak256("halt"), pk);
        vm.prank(MM);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector,
                LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
                newImpl
            )
        );
        orchestrator.mint(address(vault), eoa, 1e18, auth, "");

        vm.prank(MM);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector,
                LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
                newImpl
            )
        );
        orchestrator.burn(address(vault), 1e18, "");
    }
}
