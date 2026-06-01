// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibProdAuthoriser} from "../../../src/lib/LibProdAuthoriser.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title LibProdAuthoriserTest
/// @notice Fork tests pinning the live ST0x authoriser's role-grant map
/// against the constants in `LibProdAuthoriser`. Iterates
/// `expectedGrants()` and asserts `hasRole(role, grantee) == true` for
/// every pair; any drift (a pin missing on-chain, or an off-chain pin
/// the lib doesn't know about) surfaces here.
/// @dev Uses an unpinned Base head fork (same precedent as the other
/// prod-state drift detectors in this repo). Pinning would freeze the
/// invariant assertions against a stale snapshot and let new drift slip
/// through unnoticed.
contract LibProdAuthoriserTest is Test {
    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Live drift detector; see contract-level rationale.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice Every pinned `(role, grantee)` pair in `expectedGrants()` is
    /// held on the live authoriser. Passes against the live chain state.
    function testExpectedGrantsAllPresent() external {
        selectBaseFork();
        IAccessControl authoriser = IAccessControl(LibProdAuthoriser.STOX_PROD_AUTHORISER);
        LibProdAuthoriser.RoleGrant[] memory grants = LibProdAuthoriser.expectedGrants();
        for (uint256 i = 0; i < grants.length; i++) {
            assertTrue(
                authoriser.hasRole(grants[i].role, grants[i].grantee), "expected grant missing on live authoriser"
            );
        }
    }
}
