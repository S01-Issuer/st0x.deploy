// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibTokenOwnership, IOwnable, ReceiptVaultOwnerMismatch} from "../../../src/lib/LibTokenOwnership.sol";
import {LibProdSafes} from "../../../src/lib/LibProdSafes.sol";
import {LibRainDeploy} from "rain-deploy-0.1.2/src/lib/LibRainDeploy.sol";

/// @title LibTokenOwnershipHarness
/// @notice External-call harness so `vm.expectRevert` can intercept the
/// typed `ReceiptVaultOwnerMismatch` revert. `expectRevert` only catches
/// reverts originating at a lower call depth than the cheatcode itself;
/// library `internal` calls inline.
contract LibTokenOwnershipHarness {
    function callAssertUniformOwnership(address expected) external view {
        LibTokenOwnership.assertUniformOwnership(expected);
    }
}

/// @title LibTokenOwnershipTest
/// @notice Live fork tests pinning every ST0x receipt vault to the same
/// `owner()` (the ST0x token-owner Safe), plus an inverted test that
/// injects drift via `vm.mockCall` on a single vault and asserts the
/// typed `ReceiptVaultOwnerMismatch` revert surfaces it. Uses an unpinned
/// head fork to keep the assertion live; see precedent in
/// `LibProdSafes.t.sol::selectBaseFork`.
contract LibTokenOwnershipTest is Test {
    /// @notice External-call harness allocated per test against the
    /// active fork. Recreated by `selectBaseFork` because
    /// `vm.createSelectFork` resets cheatcode state.
    LibTokenOwnershipHarness internal harness;

    /// @notice Selects the Base fork at chain head — deliberately
    /// unpinned. The vault `owner()` set should track live state so the
    /// next CI run flags any drift.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        harness = new LibTokenOwnershipHarness();
    }

    /// @notice Live positive test: every receipt vault returned by
    /// `productionReceiptVaults()` has `owner() == STOX_TOKEN_OWNER_SAFE`.
    function testAssertUniformOwnershipLive() external {
        selectBaseFork();
        LibTokenOwnership.assertUniformOwnership(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice `productionReceiptVaults()` returns 13 entries — the
    /// current registry set. Drift here would mean the registry got a new
    /// (or lost an) entry without the constants being updated.
    function testProductionReceiptVaultsCount() external pure {
        address[] memory vaults = LibTokenOwnership.productionReceiptVaults();
        assertEq(vaults.length, 13, "expected 13 production vaults");
    }

    /// @notice Inverted test: mock the NVDA vault's `owner()` to a rogue
    /// address and assert `assertUniformOwnership` reverts with
    /// `ReceiptVaultOwnerMismatch` pinpointing that vault.
    function testInvertedOwnershipMismatchOnSingleVault() external {
        selectBaseFork();
        address rogueOwner = address(0xBADC0DE);
        address victimVault = LibTokenOwnership.ST0X_RECEIPT_VAULT_NVDA;
        vm.mockCall(victimVault, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));

        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultOwnerMismatch.selector, victimVault, LibProdSafes.STOX_TOKEN_OWNER_SAFE, rogueOwner
            )
        );
        harness.callAssertUniformOwnership(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }
}
