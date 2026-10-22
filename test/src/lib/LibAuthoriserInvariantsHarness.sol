// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";

/// @notice External-call harness around `LibAuthoriserInvariants`'s internal
/// asserts so `vm.expectRevert` can catch their typed errors — library-internal
/// reverts inline, and `expectRevert` only sees reverts from a lower call depth
/// than the cheatcode itself.
contract LibAuthoriserInvariantsHarness {
    function callAssertAll() external view {
        LibAuthoriserInvariants.assertAll();
    }

    function callAuthoriserForChainId(uint256 chainId) external pure returns (address) {
        return LibAuthoriserInvariants.authoriserForChainId(chainId);
    }

    function callActiveChainAuthoriser() external view returns (address) {
        return LibAuthoriserInvariants.activeChainAuthoriser();
    }

    function callAssertExpectedGrants(address authoriser) external view {
        LibAuthoriserInvariants.assertExpectedGrants(authoriser);
    }

    function callAssertExpectedGrants(address authoriser, address tokenOwnerSafe, address adminHolder) external view {
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, tokenOwnerSafe, adminHolder);
    }

    function callAssertExpectedEuGrants(address authoriser, address adminHolder, address minter) external view {
        LibAuthoriserInvariants.assertExpectedEuGrants(authoriser, adminHolder, minter);
    }

    function callAssertAdminRolesHeld(address authoriser, address adminHolder) external view {
        LibAuthoriserInvariants.assertAdminRolesHeld(authoriser, adminHolder);
    }

    function callAssertKeysHoldNoRoles(address authoriser) external view {
        LibAuthoriserInvariants.assertKeysHoldNoRoles(authoriser);
    }
}
