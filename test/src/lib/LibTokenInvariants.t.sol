// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibTokenInvariants, IOwnable, ReceiptVaultOwnerMismatch} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdSafes} from "../../../src/lib/LibProdSafes.sol";
import {LibProdTokensBase} from "../../../src/lib/LibProdTokensBase.sol";
import {LibTokenInvariantsHarness} from "./LibTokenInvariantsHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title LibTokenInvariantsTest
/// @notice Fork tests for the token-side uniformity invariants: every
/// production receipt vault on Base shares the same `owner()` and the same
/// `authorizer()`.
///
/// The uniform-ownership invariant currently holds on-chain (every vault is
/// owned by `LibProdSafes.STOX_TOKEN_OWNER_SAFE`), so the positive ownership
/// case passes. The uniform-authoriser invariant may be transiently red: at
/// the time of writing one vault (IBHG) is being migrated onto the shared
/// authoriser. Once that lands on-chain the authoriser test greens
/// automatically with no code change. The inverted ownership-drift case is
/// also exercised here for full error-path coverage.
/// @dev Uses an unpinned Base head fork (same precedent as the other
/// prod-state drift detectors in this repo), so the next CI run reflects the
/// current on-chain wiring. Pinning would freeze the invariant assertions
/// against a stale snapshot and let new drift slip through unnoticed.
contract LibTokenInvariantsTest is Test {
    /// @notice External-call harness deployed fresh per test against the
    /// active fork.
    LibTokenInvariantsHarness internal harness;

    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Live drift detector; see contract-level rationale.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        harness = new LibTokenInvariantsHarness();
    }

    /// @notice Every production receipt vault reports
    /// `LibProdSafes.STOX_TOKEN_OWNER_SAFE` as its `owner()`. Passes against
    /// the live chain state: vault ownership is uniform.
    function testProdReceiptVaultsUniformOwnership() external {
        selectBaseFork();
        LibTokenInvariants.assertUniformOwnership(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice Every production receipt vault reports
    /// `LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER`. May be transiently
    /// red while IBHG's authoriser is migrated on-chain; greens automatically
    /// once that lands.
    function testProdReceiptVaultsShareUniformAuthoriser() external {
        selectBaseFork();
        LibTokenInvariants.assertUniformAuthoriser(LibProdTokensBase.PROD_RECEIPT_VAULT_AUTHORISER);
    }

    /// @notice Token-side ownership drift trips `ReceiptVaultOwnerMismatch`.
    /// Simulated by mocking a single vault's `owner()` to a rogue address;
    /// the assertion reverts surfacing the offending vault. The victim vault
    /// address comes from `LibProdTokensBase` (the source of truth for
    /// production receipt vaults).
    function testInvertedUniformOwnershipDrift() external {
        selectBaseFork();
        address expectedOwner = LibProdSafes.STOX_TOKEN_OWNER_SAFE;
        address rogueOwner = address(0xBADC0DE);
        address victim = LibProdTokensBase.MSTR_RECEIPT_VAULT;
        vm.mockCall(victim, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, victim, expectedOwner, rogueOwner));
        harness.callAssertUniformOwnership(expectedOwner);
    }
}
