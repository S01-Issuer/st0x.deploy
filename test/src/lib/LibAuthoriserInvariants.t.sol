// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {
    LibAuthoriserInvariants,
    UnexpectedDefaultAdmin,
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
}
