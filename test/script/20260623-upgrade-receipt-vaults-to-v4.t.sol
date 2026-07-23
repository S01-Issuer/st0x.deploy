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
import {
    UpgradeReceiptVaultsToV4,
    V4ImplementationNotDeployed,
    V4CodehashMismatch
} from "../../script/20260623-upgrade-receipt-vaults-to-v4.s.sol";

/// @title UpgradeReceiptVaultsToV4Test
/// @notice Live-fork pin of the vault-authoriser swap executed by
/// `script/20260623-upgrade-receipt-vaults-to-v4.s.sol`: every production
/// receipt vault's `authorizer()` must be the current production
/// authoriser (`LibAuthoriserInvariants.STOX_PROD_AUTHORISER` — the V4
/// clone).
///
/// @dev The swap bundle has executed on Base, so every vault reports the
/// V4 clone and this is a live drift detector rather than a pre-authored
/// pin.
///
/// Uses an unpinned Base head fork (live drift detector).
contract UpgradeReceiptVaultsToV4Test is Test {
    /// @notice Every production receipt vault's `authorizer()` is the
    /// current production authoriser. Base-only — no other network carries
    /// live production receipt vaults.
    function testVaultsReportCurrentAuthoriser() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        LibTokenInvariants.assertUniformAuthoriser(LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
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
}
