// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title GuardPassesOnProductionBeaconsTest
/// @notice Workflow: a vault + receipt byte-identical to a Base production
/// token, on Base's production beacons serving the implementations the
/// orchestrator was built for, passes the vault-logic lock and mints.
contract GuardPassesOnProductionBeaconsTest is OrchestratorIntegrationTest {
    function testGuardPassesOnProductionBeacons() external {
        assertTrue(orchestrator.vaultLogicIsExpected(), "guard must pass on the production beacons");
        assertEq(
            address(vault).codehash,
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_PROXY_BASE_CODEHASH_V1,
            "vault is a production vault proxy"
        );
        assertEq(
            address(receipt).codehash,
            LibProdDeployV1.PROD_STOX_RECEIPT_PROXY_BASE_CODEHASH_V1,
            "receipt is a production receipt proxy"
        );

        (address eoa, uint256 pk) = makeAddrAndKey("guard-recipient");
        uint256 amount = 7e18;
        bytes32 nonce = keccak256("guard");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "");
        assertEq(vault.balanceOf(eoa), amount, "mint delivered against the real vault");
    }
}
