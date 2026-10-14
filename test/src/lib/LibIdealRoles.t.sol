// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibIdealRoles, ContractRoles} from "../../../src/lib/LibIdealRoles.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";

contract LibIdealRolesTest is Test {
    function testNoPairIsBothExpectedAndForbidden() external pure {
        uint256[] memory ids = LibIdealRoles.chainIds();
        for (uint256 c = 0; c < ids.length; c++) {
            ContractRoles[] memory roles = LibIdealRoles.contractRoles(ids[c]);
            for (uint256 i = 0; i < roles.length; i++) {
                for (uint256 j = 0; j < roles[i].forbidden.length; j++) {
                    assertFalse(
                        LibAuthoriserInvariants.mapAssigns(
                            roles[i].expected, roles[i].forbidden[j].role, roles[i].forbidden[j].grantee
                        )
                    );
                }
            }
        }
    }

    function testRetiringGrantsAreForbiddenNotExpected() external pure {
        RoleGrant[] memory retiring = LibAuthoriserInvariants.retiringGrants();
        uint256[] memory ids = LibIdealRoles.chainIds();
        for (uint256 c = 0; c < ids.length; c++) {
            ContractRoles memory authoriser = LibIdealRoles.contractRoles(ids[c])[0];
            for (uint256 i = 0; i < retiring.length; i++) {
                assertTrue(
                    LibAuthoriserInvariants.mapAssigns(authoriser.forbidden, retiring[i].role, retiring[i].grantee)
                );
                assertFalse(
                    LibAuthoriserInvariants.mapAssigns(authoriser.expected, retiring[i].role, retiring[i].grantee)
                );
            }
        }
    }
}
