// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibIdealRoles, ContractRoles} from "../../../src/lib/LibIdealRoles.sol";
import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {RoleGrant} from "../../../src/lib/RoleGrant.sol";

contract LibIdealRolesTest is Test {
    RoleGrant[] internal want;

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testV4AuthoriserLists() external {
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            (address safe, address timelock) = principals(nets[c].chainId);
            ContractRoles memory roles = LibIdealRoles.contractRoles(nets[c].chainId)[0];
            assertEq(roles.target, LibAuthoriserInvariants.authoriserForChainId(nets[c].chainId));

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
        SupportedNetwork[] memory nets = networks();
        address minter = LibAuthoriserInvariants.GRANTEE_EU_MINTER;
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        for (uint256 c = 0; c < nets.length; c++) {
            (, address timelock) = principals(nets[c].chainId);
            ContractRoles memory roles = LibIdealRoles.contractRoles(nets[c].chainId)[1];
            assertEq(roles.target, LibAuthoriserInvariants.euAuthoriserForChainId(nets[c].chainId));

            pushEach(adminRoles(), timelock);
            pushEach(operationalRoles(), minter);
            push("CERTIFY", signer);
            assertWant(roles.expected);
        }
    }

    function testOrchestratorLists() external {
        SupportedNetwork[] memory nets = networks();
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        for (uint256 c = 0; c < nets.length; c++) {
            (address safe, address timelock) = principals(nets[c].chainId);
            ContractRoles memory roles = LibIdealRoles.contractRoles(nets[c].chainId)[2];
            assertEq(roles.target, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);

            want.push(RoleGrant(bytes32(0), timelock));
            push("EMERGENCY", safe);
            push("MINT", signer);
            push("BURN", signer);
            assertWant(roles.expected);
        }
    }

    function testTimelockLists() external {
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            (address safe, address timelock) = principals(nets[c].chainId);
            ContractRoles memory roles = LibIdealRoles.contractRoles(nets[c].chainId)[3];
            assertEq(roles.target, timelock);

            push("PROPOSER_ROLE", safe);
            push("CANCELLER_ROLE", safe);
            want.push(RoleGrant(bytes32(0), timelock));
            push("EXECUTOR_ROLE", address(0));
            assertWant(roles.expected);
        }
    }

    function testOrchestratorRoleIdsAreTheInstanceGetters() external {
        SupportedNetwork[] memory nets = networks();
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        for (uint256 c = 0; c < nets.length; c++) {
            vm.createSelectFork(nets[c].name);
            ST0xOrchestrator instance = ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));
            (address safe,) = principals(nets[c].chainId);
            RoleGrant[] memory expected = LibIdealRoles.contractRoles(nets[c].chainId)[2].expected;
            assertTrue(contains(expected, RoleGrant(instance.MINT_ROLE(), signer)));
            assertTrue(contains(expected, RoleGrant(instance.BURN_ROLE(), signer)));
            assertTrue(contains(expected, RoleGrant(instance.EMERGENCY_ROLE(), safe)));
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
