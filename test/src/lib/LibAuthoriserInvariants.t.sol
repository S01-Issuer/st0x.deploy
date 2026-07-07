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
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";
import {ERC1167_PREFIX, ERC1167_SUFFIX} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1167Proxy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibAuthoriserInvariantsTest
/// @notice Fork tests pinning the live ST0x authoriser's role-grant map
/// against the constants in `LibAuthoriserInvariants`. The positive case
/// runs the lib's no-arg `assertAll()`, which iterates `expectedGrants()`
/// and asserts every pair against the live authoriser pinned at
/// `STOX_PROD_AUTHORISER`. Any drift (a pin missing on-chain, or an
/// off-chain pin the lib doesn't know about) surfaces as
/// `ExpectedGrantMissing` here.
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

    /// @notice The live authoriser pinned at
    /// `LibAuthoriserInvariants.STOX_PROD_AUTHORISER` holds every
    /// `expectedGrants()` pair. Passes against the live chain state.
    function testAssertAllPasses() external {
        selectBaseFork();
        LibAuthoriserInvariants.assertAll();
    }

    /// @notice `assertImplPinned` reverts when the authoriser's runtime
    /// codehash is not the EIP-1167 minimal proxy of the pinned impl.
    function testAssertImplPinnedRejectsWrongCodehash() external {
        selectBaseFork();
        address fake = makeAddr("fakeAuthoriser");
        vm.etch(fake, hex"600160005260206000f3");
        bytes32 expected = keccak256(
            abi.encodePacked(ERC1167_PREFIX, LibAuthoriserInvariants.STOX_PROD_AUTHORISER_IMPL, ERC1167_SUFFIX)
        );
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(abi.encodeWithSelector(AuthoriserImplCodehashMismatch.selector, fake, expected, fake.codehash));
        harness.callAssertImplPinned(fake);
    }

    /// @notice `assertExpectedGrants` reverts `UnexpectedDefaultAdmin` when a
    /// pinned grantee holds `DEFAULT_ADMIN_ROLE`.
    function testAssertExpectedGrantsRejectsDefaultAdmin() external {
        selectBaseFork();
        address auth = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;
        vm.mockCall(
            auth,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector, bytes32(0), LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE
            ),
            abi.encode(true)
        );
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedDefaultAdmin.selector, auth, LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE
            )
        );
        harness.callAssertExpectedGrants(auth);
    }
}
