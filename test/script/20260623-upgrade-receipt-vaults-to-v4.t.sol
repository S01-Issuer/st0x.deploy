// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibMigrationInvariant} from "../../src/lib/LibMigrationInvariant.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title UpgradeReceiptVaultsToV4Test
/// @notice Live-fork pin of the vault-authoriser transition executed by
/// `script/20260623-upgrade-receipt-vaults-to-v4.s.sol`. Reads each
/// production receipt vault's `authorizer()` from Base head and asserts,
/// via `LibMigrationInvariant`, that the value is either the current V3
/// authoriser (`LibAuthoriserInvariants.STOX_PROD_AUTHORISER`) or the
/// pinned V4 clone (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`) — up
/// until `V4_SWAP_DEADLINE`. From that timestamp on only the V4 clone is
/// accepted.
///
/// @dev While the V4 clone pin is still `address(0)` (post-Bundle-1
/// hydration PR has not yet landed), the migration invariant collapses to
/// "must be V3 authoriser" — every live vault reports the V3 authoriser and
/// passes. Once the clone is pinned + the swap script has run on Base, the
/// live reads flip to the V4 clone and the same test still passes. If the
/// deadline arrives and the swap has not landed on-chain, the test trips
/// `MigrationDeadlinePassed` on the first vault it visits — cron red-lines
/// and forces the operator to run the swap, extend the deadline, or delete
/// the invariant.
///
/// Uses an unpinned Base head fork so `block.timestamp` is real. Pinning a
/// block would freeze the deadline check to whichever timestamp the pinned
/// block carried, which is exactly the wrong behaviour for a deadline-gated
/// invariant.
contract UpgradeReceiptVaultsToV4Test is Test {
    /// @notice Unix timestamp past which only the V4 clone is accepted as
    /// the vault authoriser. `2026-11-01T00:00:00Z`.
    /// @dev PLACEHOLDER — set to the operator SLA for the V4 upgrade +
    /// authoriser swap on Base. Adjust before merge if the intended cut-off
    /// is different.
    uint256 internal constant V4_SWAP_DEADLINE = 1_793_491_200;

    /// @notice Every production receipt vault's `authorizer()` is either
    /// the pinned V3 authoriser or the pinned V4 clone. Base-only —
    /// no other network carries live production receipt vaults.
    function testVaultAuthoriserInMigrationWindow() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            LibMigrationInvariant.assertMigration(
                "receiptVault.authorizer()",
                address(IAuthorizableV1(vaults[i]).authorizer()),
                LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
                V4_SWAP_DEADLINE
            );
        }
    }
}
