// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {IST0xOrchestratorV1, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title GuardHaltsAfterVaultBeaconUpgradeTest
/// @notice Workflow: upgrading a production beacon to a different
/// implementation, as the beacon owner, breaks the orchestrator's version
/// lock: `vaultLogicIsExpected` flips false and both `mint` and `burn` revert.
contract GuardHaltsAfterVaultBeaconUpgradeTest is OrchestratorIntegrationTest {
    function _upgrade(address beacon) internal returns (address) {
        address newImpl = address(new ST0xOrchestrator());
        vm.prank(BEACON_OWNER);
        UpgradeableBeacon(beacon).upgradeTo(newImpl);
        assertFalse(orchestrator.vaultLogicIsExpected(), "guard halts after the beacon upgrade");
        return newImpl;
    }

    function _assertMintAndBurnHalt(bytes memory err) internal {
        (address eoa, uint256 pk) = makeAddrAndKey("halt-recipient");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, 1e18, keccak256("halt"), pk);
        vm.prank(MM);
        vm.expectRevert(err);
        orchestrator.mint(address(vault), eoa, 1e18, auth, "");

        vm.prank(MM);
        vm.expectRevert(err);
        orchestrator.burn(address(vault), 1e18, "");
    }

    function testGuardHaltsAfterVaultBeaconUpgrade() external {
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard passes before the upgrade");
        address newImpl = _upgrade(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1);
        _assertMintAndBurnHalt(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector, LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE, newImpl
            )
        );
    }

    function testGuardHaltsAfterReceiptBeaconUpgrade() external {
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard passes before the upgrade");
        address newImpl = _upgrade(LibProdDeployV1.STOX_RECEIPT_BEACON_V1);
        _assertMintAndBurnHalt(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.ReceiptLogicMismatch.selector, LibProdDeployV4.STOX_RECEIPT_CANDIDATE, newImpl
            )
        );
    }
}
