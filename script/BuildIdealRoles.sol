// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibIdealRoles, ContractRoles} from "../src/lib/LibIdealRoles.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {RoleGrant} from "../src/lib/RoleGrant.sol";

/// @notice A role in an ideal list has no constant name here.
/// @param role The role.
error UnnamedRole(bytes32 role);

/// @notice A grantee in an ideal list has no constant name on its chain.
/// @param chainId The chain id.
/// @param grantee The grantee.
error UnnamedGrantee(uint256 chainId, address grantee);

/// @notice A chain without a network name.
/// @param chainId The chain id.
error UnnamedChain(uint256 chainId);

/// @title BuildIdealRoles
/// @notice Writes `ideal-roles.json` from `LibIdealRoles`.
contract BuildIdealRoles is Script {
    string internal constant PATH = "ideal-roles.json";

    function network(uint256 chainId) internal pure returns (string memory) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return LibRainDeploy.BASE;
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) return LibStoxDeployNetworks.ETHEREUM;
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return LibStoxDeployNetworks.HYPEREVM;
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return LibStoxDeployNetworks.ROBINHOOD;
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return LibStoxDeployNetworks.BSC;
        revert UnnamedChain(chainId);
    }

    function suffix(uint256 chainId) internal pure returns (string memory) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return "";
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) return "_ETHEREUM";
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) return "_HYPEREVM";
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) return "_ROBINHOOD";
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) return "_BSC";
        revert UnnamedChain(chainId);
    }

    function roleName(bytes32 role) internal pure returns (string memory) {
        if (role == bytes32(0)) return "DEFAULT_ADMIN_ROLE";
        string[7] memory vault = [
            "DEPOSIT",
            "WITHDRAW",
            "CERTIFY",
            "CONFISCATE_SHARES",
            "CONFISCATE_RECEIPT",
            "SCHEDULE_CORPORATE_ACTION",
            "CANCEL_CORPORATE_ACTION"
        ];
        for (uint256 i = 0; i < vault.length; i++) {
            if (role == keccak256(bytes(vault[i]))) return vault[i];
            string memory admin = string.concat(vault[i], "_ADMIN");
            if (role == keccak256(bytes(admin))) return admin;
        }
        string[3] memory orchestrator = ["MINT", "BURN", "EMERGENCY"];
        for (uint256 i = 0; i < orchestrator.length; i++) {
            if (role == keccak256(bytes(orchestrator[i]))) return string.concat(orchestrator[i], "_ROLE");
        }
        string[3] memory timelock = ["PROPOSER_ROLE", "EXECUTOR_ROLE", "CANCELLER_ROLE"];
        for (uint256 i = 0; i < timelock.length; i++) {
            if (role == keccak256(bytes(timelock[i]))) return timelock[i];
        }
        revert UnnamedRole(role);
    }

    function granteeName(uint256 chainId, address grantee) internal pure returns (string memory) {
        if (grantee == LibSafeInvariants.safeForChainId(chainId)) {
            return string.concat("STOX_TOKEN_OWNER_SAFE", suffix(chainId));
        }
        if (grantee == LibTimelockInvariants.timelockForChainId(chainId)) {
            return string.concat("STOX_GOVERNANCE_TIMELOCK", suffix(chainId));
        }
        if (grantee == LibAuthoriserInvariants.GRANTEE_SERVICE_1C66) return "GRANTEE_SERVICE_1C66";
        if (grantee == LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C) return "GRANTEE_SERVICE_3D0C";
        if (grantee == LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR) return "GRANTEE_ORCHESTRATOR";
        if (grantee == LibAuthoriserInvariants.GRANTEE_EU_MINTER) return "GRANTEE_EU_MINTER";
        if (grantee == address(0)) return "address(0)";
        revert UnnamedGrantee(chainId, grantee);
    }

    function contractName(uint256 chainId, uint256 index) internal pure returns (string memory) {
        string[4] memory names =
            ["STOX_PROD_AUTHORISER_V4_CLONE", "STOX_EU_AUTHORISER_CLONE", "", "STOX_GOVERNANCE_TIMELOCK"];
        if (index == 2) return "ST0X_ORCHESTRATOR_INSTANCE";
        return string.concat(names[index], suffix(chainId));
    }

    function contractKind(uint256 index) internal pure returns (string memory) {
        string[4] memory kinds = ["AUTHORIZER", "AUTHORIZER", "ORCHESTRATOR", "GOVERNANCE_TIMELOCK"];
        return kinds[index];
    }

    function hex20(address a) internal pure returns (string memory) {
        return vm.toLowercase(vm.toString(a));
    }

    function grantsJson(uint256 chainId, RoleGrant[] memory grants) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < grants.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "\n" : ",\n",
                "            {\"role\": \"",
                vm.toString(grants[i].role),
                "\", \"roleName\": \"",
                roleName(grants[i].role),
                "\", \"grantee\": \"",
                hex20(grants[i].grantee),
                "\", \"granteeName\": \"",
                granteeName(chainId, grants[i].grantee),
                "\"}"
            );
        }
        return string.concat(json, grants.length == 0 ? "]" : "\n          ]");
    }

    function chainJson(uint256 chainId) internal pure returns (string memory) {
        ContractRoles[] memory roles = LibIdealRoles.contractRoles(chainId);
        string memory json =
            string.concat("    \"", vm.toString(chainId), "\": {\n      \"network\": \"", network(chainId), "\",\n");
        json = string.concat(json, "      \"contracts\": [");
        for (uint256 i = 0; i < roles.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "\n" : ",\n",
                "        {\n          \"address\": \"",
                hex20(roles[i].target),
                "\",\n          \"name\": \"",
                contractName(chainId, i),
                "\",\n          \"kind\": \"",
                contractKind(i),
                "\",\n          \"expected\": ",
                grantsJson(chainId, roles[i].expected),
                ",\n          \"forbidden\": ",
                grantsJson(chainId, roles[i].forbidden),
                "\n        }"
            );
        }
        return string.concat(json, "\n      ]\n    }");
    }

    function render() public pure returns (string memory) {
        uint256[] memory ids = LibIdealRoles.chainIds();
        string memory out = "{\n  \"version\": 1,\n  \"chains\": {";
        for (uint256 i = 0; i < ids.length; i++) {
            out = string.concat(out, i == 0 ? "\n" : ",\n", chainJson(ids[i]));
        }
        return string.concat(out, "\n  }\n}\n");
    }

    function run() external {
        vm.writeFile(PATH, render());
    }
}
