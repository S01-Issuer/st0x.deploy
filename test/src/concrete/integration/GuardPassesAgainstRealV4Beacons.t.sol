// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IST0xVaultBeaconSet} from "../../../../src/interface/IST0xVaultBeaconSet.sol";
import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {LibProdDeployV4} from "../../../../src/lib/LibProdDeployV4.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title GuardPassesAgainstRealV4BeaconsTest
/// @notice Workflow: the orchestrator's hardcoded vault-version guard reads
/// the REAL deterministic OARV beacon-set deployer and its two beacons, and
/// finds them pointing at the real V4 impls — so `vaultLogicIsExpected()` is
/// true and a mint against a real vault completes.
contract GuardPassesAgainstRealV4BeaconsTest is OrchestratorIntegrationTest {
    function testGuardPassesAgainstRealV4Beacons() external {
        // The guard reads the genuine production deployer + beacons.
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard must pass against the real V4 beacons");

        // Cross-check the beacons the guard reads really are the V4 impls.
        IST0xVaultBeaconSet beaconSet =
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6);
        assertEq(
            beaconSet.iOffchainAssetReceiptVaultBeacon().implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6,
            "vault beacon points at V4 vault impl"
        );
        assertEq(
            beaconSet.iReceiptBeacon().implementation(),
            LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6,
            "receipt beacon points at V4 receipt impl"
        );

        // And a mint against the real vault goes through with the guard live.
        (address eoa, uint256 pk) = makeAddrAndKey("guard-recipient");
        uint256 amount = 7e18;
        bytes32 nonce = keccak256("guard");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "");
        assertEq(vault.balanceOf(eoa), amount, "mint delivered against the real vault");
    }
}
