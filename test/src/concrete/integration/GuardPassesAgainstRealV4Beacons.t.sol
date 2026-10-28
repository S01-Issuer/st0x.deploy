// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV2.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";
import {SignedContextV1} from "rainlang-interface-0.2.15/src/interface/IInterpreterCallerV4.sol";

/// @title GuardPassesAgainstRealV4BeaconsTest
/// @notice Workflow: the orchestrator's vault-logic guard reads a real
/// token's beacon and its receipt's from their proxy bytecode, and finds
/// them serving the real V4 impls — so `vaultLogicIsExpected(vault)` is true
/// and a mint against the real vault completes.
contract GuardPassesAgainstRealV4BeaconsTest is OrchestratorIntegrationTest {
    function testGuardPassesAgainstRealV4Beacons() external {
        // The guard reads the real token's own beacons.
        assertTrue(orchestrator.vaultLogicIsExpected(address(vault)), "guard must pass against the real V4 beacons");

        // Cross-check the beacons the guard reads really are the V4 impls.
        assertEq(
            IBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE,
            "vault beacon points at V4 vault impl"
        );
        assertEq(
            IBeacon(LibProdDeployV1.STOX_RECEIPT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_RECEIPT_CANDIDATE,
            "receipt beacon points at V4 receipt impl"
        );

        // And a mint against the real vault goes through with the guard live.
        (address eoa, uint256 pk) = makeAddrAndKey("guard-recipient");
        _allowRecipient(eoa);
        uint256 amount = 7e18;
        bytes32 nonce = keccak256("guard");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "", new SignedContextV1[](0));
        assertEq(vault.balanceOf(eoa), amount, "mint delivered against the real vault");
    }
}
