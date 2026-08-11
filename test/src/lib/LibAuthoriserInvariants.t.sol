// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {
    LibAuthoriserInvariants,
    RoleGrant,
    ExpectedGrantMissing,
    UnexpectedDefaultAdmin,
    UnexpectedRetainedAdminGrant,
    AuthoriserImplCodehashMismatch
} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibAuthoriserInvariantsTest
/// @notice Fork tests pinning the production V4 authoriser clone's state
/// against the constants in `LibAuthoriserInvariants`. The positive case
/// runs the lib's no-arg `assertAll()`, which checks the clone's codehash
/// against the `LibProdDeployV4` pin and iterates the master
/// `expectedGrants()` map against the live clone. Any drift (a grant
/// missing on-chain, or the clone's bytecode changing) surfaces as a typed
/// error here.
/// @dev Uses an unpinned Base head fork (same precedent as the other
/// prod-state drift detectors in this repo). Pinning would freeze the
/// invariant assertions against a stale snapshot and let new drift slip
/// through unnoticed.
contract LibAuthoriserInvariantsTest is Test {
    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Live drift detector; see contract-level rationale.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice The production V4 clone pinned in `LibProdDeployV4` holds
    /// every `expectedGrants()` pair and its codehash matches the pin.
    /// Passes against the live chain state.
    function testAssertAllPasses() external {
        selectBaseFork();
        LibAuthoriserInvariants.assertAll();
    }

    /// @notice `assertAll` reverts `AuthoriserImplCodehashMismatch` when the
    /// clone's runtime codehash drifts from the pinned EIP-1167 runtime.
    /// Simulated by etching alien bytecode over the pinned clone address.
    function testAssertAllRejectsWrongCodehash() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        vm.etch(clone, hex"600160005260206000f3");
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthoriserImplCodehashMismatch.selector,
                clone,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
                clone.codehash
            )
        );
        harness.callAssertAll();
    }

    /// @notice `assertExpectedGrants` reverts `UnexpectedDefaultAdmin` when a
    /// pinned grantee holds `DEFAULT_ADMIN_ROLE`.
    function testAssertExpectedGrantsRejectsDefaultAdmin() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        vm.mockCall(
            clone,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector, bytes32(0), LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE
            ),
            abi.encode(true)
        );
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedDefaultAdmin.selector, clone, LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE
            )
        );
        harness.callAssertExpectedGrants(clone);
    }

    /// @notice The admin-holder parameterisation: the seven `_ADMIN` entries
    /// track `adminHolder`, the six operational entries stay split between
    /// the service signer and the Safe, and the narrower overloads are exact
    /// collapses of the widest one (so no consumer can drift from the single
    /// map).
    function testExpectedGrantsAdminHolderParameterisation() external pure {
        address safe = address(0x5AFE);
        address timelock = address(0x7135);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        assertEq(grants.length, 16);
        for (uint256 i = 0; i < 7; i++) {
            assertEq(grants[i].grantee, timelock, "admin entries must track adminHolder");
        }
        for (uint256 i = 7; i < 10; i++) {
            assertEq(grants[i].grantee, LibAuthoriserInvariants.GRANTEE_SERVICE_1C66);
        }
        for (uint256 i = 10; i < 13; i++) {
            assertEq(grants[i].grantee, safe, "operational Safe entries must track the Safe");
        }
        // The additional service signer's three action roles are operational,
        // not admin: they must track the signer regardless of who holds the
        // `_ADMIN` slice, so the timelock migration never moves them.
        for (uint256 i = 13; i < 16; i++) {
            assertEq(
                grants[i].grantee,
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C,
                "additional service signer entries must be independent of adminHolder"
            );
        }

        // The two-arg overload is the adminHolder == Safe collapse.
        RoleGrant[] memory collapsed = LibAuthoriserInvariants.expectedGrants(safe);
        RoleGrant[] memory widened = LibAuthoriserInvariants.expectedGrants(safe, safe);
        assertEq(collapsed.length, widened.length);
        for (uint256 i = 0; i < collapsed.length; i++) {
            assertEq(collapsed[i].role, widened[i].role);
            assertEq(collapsed[i].grantee, widened[i].grantee);
        }
    }

    /// @notice `assertExpectedGrants(authoriser, safe, adminHolder)` demands
    /// the exact post-timelock-migration shape: it pinpoints the first
    /// missing `_ADMIN` grant while the admin holder holds nothing, rejects
    /// the dual-holder state where the Safe retains an `_ADMIN` copy
    /// alongside the admin holder (an instant delay bypass), and passes only
    /// once the seven `_ADMIN` roles sit exclusively on the admin holder.
    function testAssertExpectedGrantsWithDistinctAdminHolder() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address safe = LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE;
        address timelock = address(0x7135);
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();

        // Without the timelock holding anything, the first `_ADMIN` entry is
        // reported missing for the timelock.
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, grants[0].role, timelock));
        harness.callAssertExpectedGrants(clone, safe, timelock);

        // Mock the seven `_ADMIN` grants onto the timelock. The live fork's
        // Safe still holds its `_ADMIN` copies, so this is the dual-holder
        // state — the Safe could still mutate the grant map without the
        // timelock's delay — and the assertion must reject it.
        for (uint256 i = 0; i < 7; i++) {
            vm.mockCall(
                clone,
                abi.encodeWithSelector(IAccessControl.hasRole.selector, grants[i].role, timelock),
                abi.encode(true)
            );
        }
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRetainedAdminGrant.selector, clone, grants[0].role, safe));
        harness.callAssertExpectedGrants(clone, safe, timelock);

        // Mock the Safe's seven `_ADMIN` copies away — the renounces landing
        // — and the full assertion passes: exclusive admin holding, with the
        // operational entries already live on the fork.
        for (uint256 i = 0; i < 7; i++) {
            vm.mockCall(
                clone,
                abi.encodeWithSelector(IAccessControl.hasRole.selector, grants[i].role, safe),
                abi.encode(false)
            );
        }
        harness.callAssertExpectedGrants(clone, safe, timelock);
    }
}
