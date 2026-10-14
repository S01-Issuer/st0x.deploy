// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    CERTIFY,
    CONFISCATE_RECEIPT,
    CONFISCATE_SHARES,
    DEPOSIT,
    WITHDRAW
} from "rain-vats-0.2.4/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    CERTIFY_ADMIN,
    CONFISCATE_RECEIPT_ADMIN,
    CONFISCATE_SHARES_ADMIN,
    DEPOSIT_ADMIN,
    WITHDRAW_ADMIN
} from "rain-vats-0.2.4/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {UnnamedChain, UnnamedGrantee, UnnamedRole} from "../../script/BuildIdealRoles.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {
    CANCEL_CORPORATE_ACTION_ADMIN,
    SCHEDULE_CORPORATE_ACTION_ADMIN
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {CANCEL_CORPORATE_ACTION, SCHEDULE_CORPORATE_ACTION} from "../../src/lib/LibCorporateAction.sol";
import {LibIdealRoles, ContractRoles} from "../../src/lib/LibIdealRoles.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";
import {BuildIdealRolesHarness} from "./BuildIdealRolesHarness.sol";

struct Named {
    string name;
    address value;
}

contract BuildIdealRolesTest is Test {
    BuildIdealRolesHarness internal build = new BuildIdealRolesHarness();

    function testVersionIsOne() external view {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testChainsAreKeyedByIdWithTheirNetworkNames() external view {
        string memory json = build.render();
        assertEq(vm.parseJsonKeys(json, ".chains").length, 5);
        string[5] memory ids = ["8453", "1", "999", "4663", "56"];
        string[5] memory networks = ["base", "ethereum", "hyperevm", "robinhood", "bsc"];
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(vm.parseJsonString(json, string.concat(".chains.", ids[i], ".network")), networks[i]);
        }
    }

    function testContractsCarryTheirConstantNamesAndKinds() external view {
        string memory json = build.render();
        string[4] memory kinds = ["AUTHORIZER", "AUTHORIZER", "ORCHESTRATOR", "GOVERNANCE_TIMELOCK"];
        uint256[] memory ids = LibIdealRoles.chainIds();
        for (uint256 c = 0; c < ids.length; c++) {
            ContractRoles[] memory roles = LibIdealRoles.contractRoles(ids[c]);
            string memory at = string.concat(".chains.", vm.toString(ids[c]), ".contracts");
            assertFalse(vm.keyExistsJson(json, index(at, kinds.length)));
            for (uint256 i = 0; i < kinds.length; i++) {
                string memory entry = index(at, i);
                assertEq(vm.parseJsonAddress(json, string.concat(entry, ".address")), roles[i].target);
                assertLowercase(vm.parseJsonString(json, string.concat(entry, ".address")));
                assertEq(
                    contractNamed(ids[c], vm.parseJsonString(json, string.concat(entry, ".name"))), roles[i].target
                );
                assertEq(vm.parseJsonString(json, string.concat(entry, ".kind")), kinds[i]);
            }
        }
    }

    function testRowsCarryTheListsUnderTheirConstantNames() external view {
        string memory json = build.render();
        uint256[] memory ids = LibIdealRoles.chainIds();
        for (uint256 c = 0; c < ids.length; c++) {
            ContractRoles[] memory roles = LibIdealRoles.contractRoles(ids[c]);
            for (uint256 i = 0; i < roles.length; i++) {
                string memory at = index(string.concat(".chains.", vm.toString(ids[c]), ".contracts"), i);
                assertRows(json, ids[c], string.concat(at, ".expected"), roles[i].expected);
            }
        }
    }

    function testOrchestratorRoleNamesAreTheInstanceGetters() external {
        string[5] memory networks = ["base", "ethereum", "hyperevm", "robinhood", "bsc"];
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            ST0xOrchestrator instance = ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));
            assertEq(instance.MINT_ROLE(), roleNamed("MINT_ROLE"));
            assertEq(instance.BURN_ROLE(), roleNamed("BURN_ROLE"));
            assertEq(instance.EMERGENCY_ROLE(), roleNamed("EMERGENCY_ROLE"));
        }
    }

    function testRunWritesTheRender() external {
        build.run();
        assertEq(vm.readFile("ideal-roles.json"), build.render());
    }

    function testUnknownChainHasNoNetwork() external {
        vm.expectRevert(abi.encodeWithSelector(UnnamedChain.selector, uint256(10)));
        build.callNetwork(10);
    }

    function testUnknownChainHasNoSuffix() external {
        vm.expectRevert(abi.encodeWithSelector(UnnamedChain.selector, uint256(10)));
        build.callSuffix(10);
    }

    function testUnknownRoleHasNoName() external {
        bytes32 role = keccak256("TRANSFER_SHARES");
        vm.expectRevert(abi.encodeWithSelector(UnnamedRole.selector, role));
        build.callRoleName(role);
    }

    function testUnknownGranteeHasNoName() external {
        address grantee = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        vm.expectRevert(abi.encodeWithSelector(UnnamedGrantee.selector, uint256(1), grantee));
        build.callGranteeName(1, grantee);
    }

    function assertRows(string memory json, uint256 chainId, string memory at, RoleGrant[] memory grants)
        internal
        view
    {
        assertFalse(vm.keyExistsJson(json, index(at, grants.length)));
        for (uint256 j = 0; j < grants.length; j++) {
            string memory row = index(at, j);
            assertEq(vm.parseJsonBytes32(json, string.concat(row, ".role")), grants[j].role);
            assertEq(roleNamed(vm.parseJsonString(json, string.concat(row, ".roleName"))), grants[j].role);
            assertEq(vm.parseJsonAddress(json, string.concat(row, ".grantee")), grants[j].grantee);
            assertLowercase(vm.parseJsonString(json, string.concat(row, ".grantee")));
            assertEq(
                granteeNamed(chainId, vm.parseJsonString(json, string.concat(row, ".granteeName"))), grants[j].grantee
            );
        }
    }

    function roleNamed(string memory name) internal pure returns (bytes32) {
        bytes32 key = keccak256(bytes(name));
        if (key == keccak256("DEFAULT_ADMIN_ROLE")) return LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE;
        if (key == keccak256("DEPOSIT")) return DEPOSIT;
        if (key == keccak256("WITHDRAW")) return WITHDRAW;
        if (key == keccak256("CERTIFY")) return CERTIFY;
        if (key == keccak256("CONFISCATE_SHARES")) return CONFISCATE_SHARES;
        if (key == keccak256("CONFISCATE_RECEIPT")) return CONFISCATE_RECEIPT;
        if (key == keccak256("SCHEDULE_CORPORATE_ACTION")) return SCHEDULE_CORPORATE_ACTION;
        if (key == keccak256("CANCEL_CORPORATE_ACTION")) return CANCEL_CORPORATE_ACTION;
        if (key == keccak256("DEPOSIT_ADMIN")) return DEPOSIT_ADMIN;
        if (key == keccak256("WITHDRAW_ADMIN")) return WITHDRAW_ADMIN;
        if (key == keccak256("CERTIFY_ADMIN")) return CERTIFY_ADMIN;
        if (key == keccak256("CONFISCATE_SHARES_ADMIN")) return CONFISCATE_SHARES_ADMIN;
        if (key == keccak256("CONFISCATE_RECEIPT_ADMIN")) return CONFISCATE_RECEIPT_ADMIN;
        if (key == keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN")) return SCHEDULE_CORPORATE_ACTION_ADMIN;
        if (key == keccak256("CANCEL_CORPORATE_ACTION_ADMIN")) return CANCEL_CORPORATE_ACTION_ADMIN;
        if (key == keccak256("MINT_ROLE")) return keccak256("MINT");
        if (key == keccak256("BURN_ROLE")) return keccak256("BURN");
        if (key == keccak256("EMERGENCY_ROLE")) return keccak256("EMERGENCY");
        if (key == keccak256("PROPOSER_ROLE")) return LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE;
        if (key == keccak256("EXECUTOR_ROLE")) return LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE;
        if (key == keccak256("CANCELLER_ROLE")) return LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE;
        revert(string.concat("no role constant named ", name));
    }

    function perChain(uint256 chainId) internal pure returns (Named[4] memory) {
        if (chainId == 8453) {
            return [
                Named("STOX_PROD_AUTHORISER_V4_CLONE", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE),
                Named("STOX_EU_AUTHORISER_CLONE", LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE),
                Named("STOX_TOKEN_OWNER_SAFE", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE),
                Named("STOX_GOVERNANCE_TIMELOCK", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK)
            ];
        }
        if (chainId == 1) {
            return [
                Named("STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM),
                Named("STOX_EU_AUTHORISER_CLONE_ETHEREUM", LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE_ETHEREUM),
                Named("STOX_TOKEN_OWNER_SAFE_ETHEREUM", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM),
                Named("STOX_GOVERNANCE_TIMELOCK_ETHEREUM", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM)
            ];
        }
        if (chainId == 999) {
            return [
                Named("STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM),
                Named("STOX_EU_AUTHORISER_CLONE_HYPEREVM", LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE_HYPEREVM),
                Named("STOX_TOKEN_OWNER_SAFE_HYPEREVM", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM),
                Named("STOX_GOVERNANCE_TIMELOCK_HYPEREVM", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM)
            ];
        }
        if (chainId == 4663) {
            return [
                Named(
                    "STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD
                ),
                Named("STOX_EU_AUTHORISER_CLONE_ROBINHOOD", LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE_ROBINHOOD),
                Named("STOX_TOKEN_OWNER_SAFE_ROBINHOOD", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD),
                Named("STOX_GOVERNANCE_TIMELOCK_ROBINHOOD", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD)
            ];
        }
        if (chainId == 56) {
            return [
                Named("STOX_PROD_AUTHORISER_V4_CLONE_BSC", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC),
                Named("STOX_EU_AUTHORISER_CLONE_BSC", LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE_BSC),
                Named("STOX_TOKEN_OWNER_SAFE_BSC", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC),
                Named("STOX_GOVERNANCE_TIMELOCK_BSC", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC)
            ];
        }
        revert(string.concat("no constants for chain ", vm.toString(chainId)));
    }

    function contractNamed(uint256 chainId, string memory name) internal pure returns (address) {
        Named[4] memory chain = perChain(chainId);
        Named[] memory table = new Named[](4);
        table[0] = chain[0];
        table[1] = chain[1];
        table[2] = Named("ST0X_ORCHESTRATOR_INSTANCE", LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
        table[3] = chain[3];
        return lookup(table, chainId, name);
    }

    function granteeNamed(uint256 chainId, string memory name) internal pure returns (address) {
        Named[4] memory chain = perChain(chainId);
        Named[] memory table = new Named[](6);
        table[0] = chain[2];
        table[1] = chain[3];
        table[2] = Named("GRANTEE_SERVICE_3D0C", LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        table[3] = Named("GRANTEE_ORCHESTRATOR", LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        table[4] = Named("GRANTEE_EU_MINTER", LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        table[5] = Named("address(0)", address(0));
        return lookup(table, chainId, name);
    }

    function lookup(Named[] memory table, uint256 chainId, string memory name) internal pure returns (address) {
        for (uint256 i = 0; i < table.length; i++) {
            if (keccak256(bytes(table[i].name)) == keccak256(bytes(name))) return table[i].value;
        }
        revert(string.concat("no constant named ", name, " on chain ", vm.toString(chainId)));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function assertLowercase(string memory value) internal pure {
        assertEq(value, vm.toLowercase(value));
    }
}
