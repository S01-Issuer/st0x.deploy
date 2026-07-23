// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {MigrationDeadlinePassed} from "../../../src/lib/LibMigrationInvariant.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTokenInvariants, IAuthorisable, ReceiptVaultNullAuthoriser} from "../../../src/lib/LibTokenInvariants.sol";
import {LibTokenInvariantsHarness} from "./LibTokenInvariantsHarness.sol";

/// @title LibTokenInvariantsMigrationTest
/// @notice Behavioural coverage of
/// `LibTokenInvariants.assertUniformAuthoriserMigration`: the unconditional
/// null-authoriser rejection and the migration-window acceptance it wraps.
///
/// The null cases use the production pins the bundle passes —
/// `pre = LibAuthoriserInvariants.STOX_PROD_AUTHORISER`,
/// `post = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`,
/// `deadline = LibProdDeployV4.V4_SWAP_DEADLINE`.
///
/// The rejection is asserted with the LIVE pins rather than a zero `post`
/// on purpose. A zero `post` is what made the original fail-open reachable:
/// a null `authorizer()` collided with the zero pin and read as "already
/// migrated". That pin is hydrated now, so the collision is gone and a null
/// would already revert — but with `MigrationStateDrift`, which names the
/// wrong fault. Rejecting null unconditionally keeps the specific error
/// correct whatever `post` holds, including if a future chain's pin is
/// added unhydrated. The window-preservation cases use non-zero sentinels
/// so legitimate pre/post acceptance is pinned independently.
///
/// @dev Every vault's `authorizer()` is mocked per test, so no fork is
/// needed: the decision surface under test is pure
/// `(authorizer(), pre, post, block.timestamp)` logic, and mocking keeps
/// each branch deterministic instead of coupling it to live chain drift.
/// The live-fork drift detectors stay in `LibTokenInvariants.t.sol`.
contract LibTokenInvariantsMigrationTest is Test {
    LibTokenInvariantsHarness internal harness;

    address internal constant PRE = address(0xAAAA);
    address internal constant POST = address(0xBBBB);
    uint256 internal constant DEADLINE = 2_000_000_000;

    /// @notice The label `assertUniformAuthoriserMigration` passes to the
    /// underlying migration invariant, surfaced in its revert data.
    string internal constant AUTHORISER_LABEL = "receiptVault.authorizer()";

    function setUp() external {
        harness = new LibTokenInvariantsHarness();
    }

    /// @notice Mocks `authorizer()` on every production receipt vault:
    /// `vaults[0]` reports `victimAuthoriser`, every other vault reports
    /// `uniform`. Pass the same value for both to mock the whole set
    /// uniformly. Returns the vault list so tests can reference the victim.
    function mockVaultAuthorisers(address uniform, address victimAuthoriser)
        internal
        returns (address[] memory vaults)
    {
        vaults = LibTokenInvariants.productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            vm.mockCall(
                vaults[i],
                abi.encodeWithSelector(IAuthorisable.authorizer.selector),
                abi.encode(i == 0 ? victimAuthoriser : uniform)
            );
        }
    }

    /// @notice A vault whose `authorizer()` is `address(0)` trips
    /// `ReceiptVaultNullAuthoriser` before the deadline, under the
    /// production pins whose `post` is still `address(0)`. Pins the
    /// fail-closed reading of a null authoriser: without the unconditional
    /// rejection, `actual == post` (`0 == 0`) would accept the bricked
    /// vault as "already migrated" and the bundle would pass.
    function testNullAuthoriserRevertsBeforeDeadline() external {
        vm.warp(LibProdDeployV4.V4_SWAP_DEADLINE - 1);
        address[] memory vaults = mockVaultAuthorisers(LibAuthoriserInvariants.STOX_PROD_AUTHORISER, address(0));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultNullAuthoriser.selector, vaults[0]));
        harness.callAssertUniformAuthoriserMigration(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
    }

    /// @notice A null `authorizer()` trips `ReceiptVaultNullAuthoriser`
    /// at/after the deadline too — the rejection is independent of the
    /// migration window. Every vault is mocked to `address(0)` so the
    /// strict post-deadline branch cannot revert first on another vault:
    /// without the unconditional rejection, all-null `authorizer()`s would
    /// satisfy `actual == post` (`0 == 0`) and the bundle would pass.
    function testNullAuthoriserRevertsAfterDeadline() external {
        vm.warp(LibProdDeployV4.V4_SWAP_DEADLINE);
        address[] memory vaults = mockVaultAuthorisers(address(0), address(0));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultNullAuthoriser.selector, vaults[0]));
        harness.callAssertUniformAuthoriserMigration(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            LibProdDeployV4.V4_SWAP_DEADLINE
        );
    }

    /// @notice Before the deadline, every vault on the (non-zero) `pre`
    /// authoriser passes: the swap has not run yet and the pre-state is
    /// accepted. Pins that the null rejection does not narrow legitimate
    /// window behaviour.
    function testWindowAcceptsPreBeforeDeadline() external {
        vm.warp(DEADLINE - 1);
        mockVaultAuthorisers(PRE, PRE);
        harness.callAssertUniformAuthoriserMigration(PRE, POST, DEADLINE);
    }

    /// @notice Before the deadline, every vault on the (non-zero) `post`
    /// authoriser passes: the swap has already run and the post-state is
    /// accepted.
    function testWindowAcceptsPostBeforeDeadline() external {
        vm.warp(DEADLINE - 1);
        mockVaultAuthorisers(POST, POST);
        harness.callAssertUniformAuthoriserMigration(PRE, POST, DEADLINE);
    }

    /// @notice At/after the deadline, every vault on the (non-zero) `post`
    /// authoriser still passes: strict enforcement accepts exactly the
    /// post-state.
    function testWindowAcceptsPostAfterDeadline() external {
        vm.warp(DEADLINE);
        mockVaultAuthorisers(POST, POST);
        harness.callAssertUniformAuthoriserMigration(PRE, POST, DEADLINE);
    }

    /// @notice At/after the deadline, a vault still on the (non-zero) `pre`
    /// authoriser trips `MigrationDeadlinePassed` — the grace window has
    /// closed and only `post` is accepted.
    function testWindowRejectsPreAfterDeadline() external {
        vm.warp(DEADLINE);
        mockVaultAuthorisers(PRE, PRE);
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationDeadlinePassed.selector,
                AUTHORISER_LABEL,
                bytes32(uint256(uint160(POST))),
                bytes32(uint256(uint160(PRE))),
                DEADLINE
            )
        );
        harness.callAssertUniformAuthoriserMigration(PRE, POST, DEADLINE);
    }
}
