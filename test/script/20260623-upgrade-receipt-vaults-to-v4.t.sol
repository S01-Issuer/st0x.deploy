// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";

/// @title UpgradeReceiptVaultsToV4Test
/// @notice Live-fork pin of the vault-authoriser transition executed by
/// `script/20260623-upgrade-receipt-vaults-to-v4.s.sol`, via the same
/// migration-window leg `LibInvariants.assertAll` composes:
/// `LibTokenInvariants.assertUniformAuthoriserMigration(V3, V4 clone,
/// V4_SWAP_DEADLINE)`. Before the deadline each vault may report the V3
/// authoriser or the V4 clone; after it only the V4 clone passes and cron
/// red-lines until the swap runs, the deadline is extended, or the
/// migration is explicitly abandoned.
///
/// @dev While the V4 clone pin is still `address(0)` (clone-address PR not
/// yet landed), the window collapses to "must be V3 authoriser" — every
/// live vault reports the V3 authoriser and passes. Once the clone is
/// pinned + the swap has run on Base, the live reads flip to the V4 clone
/// and the same test still passes with no code change.
///
/// Uses an unpinned Base head fork so `block.timestamp` is real. Pinning a
/// block would freeze the deadline check to whichever timestamp the pinned
/// block carried, which is exactly the wrong behaviour for a deadline-gated
/// invariant.
contract UpgradeReceiptVaultsToV4Test is Test {
    /// @notice Every production receipt vault's `authorizer()` is within
    /// the V4 swap migration window. Base-only — no other network carries
    /// live production receipt vaults.
    function testVaultAuthoriserInMigrationWindow() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        LibTokenInvariants.assertUniformAuthoriserMigration(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
    }
}
