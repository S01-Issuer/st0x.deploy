// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibProdTokensBase} from "../../../src/lib/LibProdTokensBase.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title LibProdAuthoriserUniformityTest
/// @notice Pins that every production receipt vault on Base shares the same
/// authoriser.
///
/// This test is EXPECTED TO FAIL today and is committed red on purpose, as a
/// forcing function — the same pattern used elsewhere for prod-state drift
/// that needs an owner to resolve it. As of 2026-05-29, 12 of the 13 vaults
/// report `PROD_RECEIPT_VAULT_AUTHORISER`; IBHG still reports a different
/// authoriser (`0x6e0F1c31Fca4Ff07cD0C3e8658b1e3a473f3393a`). The assertion
/// reverts with `ReceiptVaultAuthoriserMismatch` naming IBHG until its
/// authoriser is brought into line on-chain, at which point this test greens
/// automatically with no code change.
contract LibProdAuthoriserUniformityTest is Test {
    /// @notice Selects the Base fork at chain head — deliberately unpinned, so
    /// the next CI run is the canary for the IBHG authoriser being fixed (or
    /// any new vault diverging). Matches the unpinned head-fork convention
    /// used by the other prod-state drift detectors in this repo.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice Every production receipt vault reports
    /// `LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER`. Fails until the
    /// last divergent vault (IBHG) is migrated to the shared authoriser.
    function testProdReceiptVaultsShareUniformAuthoriser() external {
        selectBaseFork();
        LibSafeInvariants.assertUniformAuthoriser(LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER);
    }
}
