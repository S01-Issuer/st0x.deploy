// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

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
}
