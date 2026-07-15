// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";

import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {IUpgradeableBeacon} from "../../src/lib/LibSafeOps.sol";
import {
    UpgradeReceiptVaultsToV4,
    V4ImplementationNotDeployed,
    V4CodehashMismatch,
    VaultAuthoriserMismatchPostUpgrade
} from "../../script/20260623-upgrade-receipt-vaults-to-v4.s.sol";
import {UpgradeReceiptVaultsToV4Harness} from "./UpgradeReceiptVaultsToV4Harness.sol";

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

    /// @notice The receipt-vault beacon whose implementation the script
    /// upgrades.
    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    /// @notice The V4 receipt-vault implementation the script upgrades the
    /// beacon to (placeholder Zoltu address until the patched build lands).
    address internal constant V4_IMPL = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1;

    /// @notice Fork Base at head. The beacon-ownership migration
    /// (`MigrateBeaconOwners.s.sol`) EXECUTED on Base in 2026-07, so the
    /// live receipt-vault beacon is already Safe-owned — the script's
    /// beacon pre-flight (`assertBeaconInvariants`, Safe-owned + at V1)
    /// passes against real chain state with no simulation, and `run()`
    /// reaches the V4 impl + clone checks.
    function _forkAndMigrateBeaconOwnership() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEq(
            Ownable(BEACON).owner(),
            LibBeaconInvariants.PROD_BEACON_OWNER,
            "live beacon not Safe-owned - migration state regressed?"
        );
    }

    /// @notice `run()` pre-flight reverts `V4ImplementationNotDeployed` when
    /// the V4 receipt-vault impl has no code at its Zoltu address. The impl is
    /// already live on Base, so the undeployed state is forced with
    /// `vm.etch(V4_IMPL, "")`. Also pins pre-flight ordering: the Safe + beacon
    /// invariants pass first (real live state + simulated #196), so the revert
    /// is specifically the V4-impl gate, not an earlier one.
    function testRunRevertsWhenV4ImplNotDeployed() external {
        _forkAndMigrateBeaconOwnership();
        vm.etch(V4_IMPL, "");
        UpgradeReceiptVaultsToV4 upgradeScript = new UpgradeReceiptVaultsToV4();
        vm.expectRevert(abi.encodeWithSelector(V4ImplementationNotDeployed.selector, V4_IMPL));
        upgradeScript.run();
    }

    /// @notice `run()` pre-flight reverts `V4CodehashMismatch` when code exists
    /// at the V4 impl address but its codehash differs from the pinned V4
    /// codehash — the on-chain bytecode is not the audited V4 build.
    function testRunRevertsWhenV4CodehashMismatches() external {
        _forkAndMigrateBeaconOwnership();
        bytes memory bogus = hex"60016000526001601ff3";
        vm.etch(V4_IMPL, bogus);
        UpgradeReceiptVaultsToV4 upgradeScript = new UpgradeReceiptVaultsToV4();
        vm.expectRevert(
            abi.encodeWithSelector(
                V4CodehashMismatch.selector,
                V4_IMPL,
                LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1,
                keccak256(bogus)
            )
        );
        upgradeScript.run();
    }

    /// @notice Happy path against unmodified live Base state: every
    /// pre-flight input is now real (beacon Safe-owned since the 2026-07
    /// migration, audited V4 impl live at `V4_IMPL` with the pinned
    /// codehash, V4 authoriser clone deployed + pinned + grant-configured),
    /// so `run()` completes end-to-end — pre-flight, bundle build,
    /// simulation, post-state, n+1 reversibility — and writes the Safe Tx
    /// Builder artifact. This is the exact dry-run the `run-script`
    /// dispatch executes to author the signable bundle.
    function testRunCompletesAndWritesArtifact() external {
        _forkAndMigrateBeaconOwnership();
        assertEq(
            V4_IMPL.codehash,
            LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1,
            "live V4 impl codehash != pinned codehash"
        );
        UpgradeReceiptVaultsToV4 upgradeScript = new UpgradeReceiptVaultsToV4();
        upgradeScript.run();

        // The artifact landed with the pinned bundle name and the expected
        // shape: 3 beacon upgrades + one setAuthorizer per production vault.
        string memory json = vm.readFile("out/v4-upgrade.json");
        assertEq(
            vm.parseJsonString(json, ".meta.name"),
            "ST0x receipt vault V4 upgrade + authoriser swap",
            "artifact bundle name"
        );
        uint256 expectedTxCount = 3 + LibTokenInvariants.productionReceiptVaults().length;
        assertTrue(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(expectedTxCount - 1), "].to")),
            "last expected tx present"
        );
        assertFalse(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(expectedTxCount), "].to")),
            "no extra txs"
        );
    }

    /// @notice `_assertPostState` reverts `VaultAuthoriserMismatchPostUpgrade`
    /// when a production vault still reports a non-V4-clone authoriser after
    /// the beacon leg. Drives all three beacons to their V4 impls (so the
    /// beacon post-state passes) but leaves authorisers un-swapped, so the
    /// per-vault loop trips on vault 0. Exercises the post-state guard the
    /// placeholder clone pin otherwise keeps `run()` from ever reaching.
    function testAssertPostStateRevertsWhenVaultNotSwapped() external {
        _forkAndMigrateBeaconOwnership();
        deployCodeTo("src/concrete/StoxReceiptVault.sol:StoxReceiptVault", V4_IMPL);
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1
        );
        // All three V1 beacons to their V4 impls (receipt + wrapped impls
        // are live on Base already; the receipt-vault impl was planted
        // above).
        vm.prank(LibBeaconInvariants.PROD_BEACON_OWNER);
        IUpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_BEACON_V1).upgradeTo(LibProdDeployV4.STOX_RECEIPT_0_1_1);
        vm.prank(LibBeaconInvariants.PROD_BEACON_OWNER);
        IUpgradeableBeacon(BEACON).upgradeTo(V4_IMPL);
        vm.prank(LibBeaconInvariants.PROD_BEACON_OWNER);
        IUpgradeableBeacon(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1)
            .upgradeTo(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1);

        UpgradeReceiptVaultsToV4Harness harness = new UpgradeReceiptVaultsToV4Harness();
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        address firstAuth = address(IAuthorizableV1(vaults[0]).authorizer());
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultAuthoriserMismatchPostUpgrade.selector,
                vaults[0],
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
                firstAuth
            )
        );
        harness.callAssertPostState(safe, vaults);
    }
}
