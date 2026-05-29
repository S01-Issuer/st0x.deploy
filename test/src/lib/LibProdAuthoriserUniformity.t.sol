// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibProdTokensBase} from "../../../src/lib/LibProdTokensBase.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title LibProdAuthoriserUniformityTest
/// @notice Focused pin on the uniform-authoriser invariant: every production
/// receipt vault on Base shares `PROD_RECEIPT_VAULT_AUTHORISER`.
///
/// This is a first-class token-side invariant — it is also folded into
/// `assertImmutableInvariants` (and therefore `assertAll`), so the production
/// Safe invariant suite carries it too. This file exists as a named,
/// standalone signal for this specific drift surface.
///
/// It may be transiently red: at the time of writing one vault (IBHG) is
/// being migrated onto the shared authoriser. Once that lands on-chain this
/// greens automatically with no code change. The unpinned head fork means the
/// next CI run is the canary for the migration completing.
contract LibProdAuthoriserUniformityTest is Test {
    /// @notice Selects the Base fork at chain head — deliberately unpinned, so
    /// the next CI run reflects the current on-chain authoriser wiring. Matches
    /// the unpinned head-fork convention used by the other prod-state drift
    /// detectors in this repo.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice Every production receipt vault reports
    /// `LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER`.
    function testProdReceiptVaultsShareUniformAuthoriser() external {
        selectBaseFork();
        LibSafeInvariants.assertUniformAuthoriser(LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER);
    }
}
