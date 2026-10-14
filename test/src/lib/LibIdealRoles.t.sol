// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibIdealRoles, ContractRoles} from "../../../src/lib/LibIdealRoles.sol";
import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";

contract LibIdealRolesTest is Test {
    RoleGrant[] internal want;

    function testChainIdsAreTheFiveDeploymentChains() external pure {
        uint256[] memory ids = LibIdealRoles.chainIds();
        assertEq(ids.length, 5);
        assertEq(ids[0], 8453);
        assertEq(ids[1], 1);
        assertEq(ids[2], 999);
        assertEq(ids[3], 4663);
        assertEq(ids[4], 56);
    }

    function testV4AuthoriserLists() external {
        uint256[] memory ids = LibIdealRoles.chainIds();
        for (uint256 c = 0; c < ids.length; c++) {
            (address safe, address timelock) = principals(ids[c]);
            ContractRoles memory roles = LibIdealRoles.contractRoles(ids[c])[0];
            assertEq(roles.target, LibAuthoriserInvariants.authoriserForChainId(ids[c]));

            pushEach(adminRoles(), timelock);
            push("DEPOSIT", safe);
            push("WITHDRAW", safe);
            push("CERTIFY", safe);
            push("CERTIFY", LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
            push("DEPOSIT", LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
            push("WITHDRAW", LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
            assertWant(roles.expected);
        }
    }

    function testEuAuthoriserLists() external {
        uint256[] memory ids = LibIdealRoles.chainIds();
        address minter = LibAuthoriserInvariants.GRANTEE_EU_MINTER;
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        for (uint256 c = 0; c < ids.length; c++) {
            (, address timelock) = principals(ids[c]);
            ContractRoles memory roles = LibIdealRoles.contractRoles(ids[c])[1];
            assertEq(roles.target, LibAuthoriserInvariants.euAuthoriserForChainId(ids[c]));

            pushEach(adminRoles(), timelock);
            pushEach(operationalRoles(), minter);
            push("CERTIFY", signer);
            assertWant(roles.expected);
        }
    }

    function testOrchestratorLists() external {
        uint256[] memory ids = LibIdealRoles.chainIds();
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        for (uint256 c = 0; c < ids.length; c++) {
            (address safe, address timelock) = principals(ids[c]);
            ContractRoles memory roles = LibIdealRoles.contractRoles(ids[c])[2];
            assertEq(roles.target, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

            want.push(RoleGrant(bytes32(0), timelock));
            push("EMERGENCY", safe);
            push("MINT", signer);
            push("BURN", signer);
            assertWant(roles.expected);
        }
    }

    function testTimelockLists() external {
        uint256[] memory ids = LibIdealRoles.chainIds();
        for (uint256 c = 0; c < ids.length; c++) {
            (address safe, address timelock) = principals(ids[c]);
            ContractRoles memory roles = LibIdealRoles.contractRoles(ids[c])[3];
            assertEq(roles.target, timelock);

            push("PROPOSER_ROLE", safe);
            push("CANCELLER_ROLE", safe);
            want.push(RoleGrant(bytes32(0), timelock));
            push("EXECUTOR_ROLE", address(0));
            assertWant(roles.expected);
        }
    }

    function principals(uint256 chainId) internal pure returns (address, address) {
        return (LibSafeInvariants.safeForChainId(chainId), LibTimelockInvariants.timelockForChainId(chainId));
    }

    function adminRoles() internal pure returns (string[7] memory) {
        return [
            "DEPOSIT_ADMIN",
            "WITHDRAW_ADMIN",
            "CERTIFY_ADMIN",
            "CONFISCATE_SHARES_ADMIN",
            "CONFISCATE_RECEIPT_ADMIN",
            "SCHEDULE_CORPORATE_ACTION_ADMIN",
            "CANCEL_CORPORATE_ACTION_ADMIN"
        ];
    }

    function operationalRoles() internal pure returns (string[7] memory) {
        return [
            "DEPOSIT",
            "WITHDRAW",
            "CERTIFY",
            "CONFISCATE_SHARES",
            "CONFISCATE_RECEIPT",
            "SCHEDULE_CORPORATE_ACTION",
            "CANCEL_CORPORATE_ACTION"
        ];
    }

    function push(string memory role, address grantee) internal {
        want.push(RoleGrant(keccak256(bytes(role)), grantee));
    }

    function pushEach(string[7] memory roles, address grantee) internal {
        for (uint256 i = 0; i < roles.length; i++) {
            push(roles[i], grantee);
        }
    }

    function contains(RoleGrant[] memory grants, RoleGrant memory grant) internal pure returns (bool) {
        for (uint256 i = 0; i < grants.length; i++) {
            if (grants[i].role == grant.role && grants[i].grantee == grant.grantee) {
                return true;
            }
        }
        return false;
    }

    function assertWant(RoleGrant[] memory actual) internal {
        RoleGrant[] memory wanted = want;
        assertEq(actual.length, wanted.length, "length");
        for (uint256 i = 0; i < wanted.length; i++) {
            assertTrue(contains(actual, wanted[i]), "wanted pair missing");
        }
        for (uint256 i = 0; i < actual.length; i++) {
            assertTrue(contains(wanted, actual[i]), "unwanted pair present");
        }
        delete want;
    }
}
