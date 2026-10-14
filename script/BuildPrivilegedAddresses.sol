// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV2BaseOverrides} from "../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice A chain without a network name.
/// @param chainId The chain id.
error UnnamedChain(uint256 chainId);

/// @notice A Safe owner without a constant name.
/// @param owner The owner.
error UnnamedOwner(address owner);

/// @notice A role in the grant map without a constant name.
/// @param role The role.
error UnnamedRole(bytes32 role);

/// @notice A grantee in the grant map without a constant name on its chain.
/// @param chainId The chain id.
/// @param grantee The grantee.
error UnnamedGrantee(uint256 chainId, address grantee);

/// @title BuildPrivilegedAddresses
/// @notice Writes `privileged-addresses.json`: the Safe policy, the per-chain
/// Safe, timelock and authoriser with its grant map, the authoriser
/// implementation and the beacon owners, each address under its constant name.
contract BuildPrivilegedAddresses is Script {
    string internal constant PATH = "privileged-addresses.json";

    function chainIds() internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](5);
        ids[0] = LibSafeInvariants.BASE_CHAIN_ID;
        ids[1] = LibSafeInvariants.ETHEREUM_CHAIN_ID;
        ids[2] = LibSafeInvariants.HYPEREVM_CHAIN_ID;
        ids[3] = LibSafeInvariants.ROBINHOOD_CHAIN_ID;
        ids[4] = LibSafeInvariants.BSC_CHAIN_ID;
        return ids;
    }

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

    function ownerName(address owner) internal pure returns (string memory) {
        if (owner == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_1) return "STOX_TOKEN_OWNER_SAFE_OWNER_1";
        if (owner == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_2) return "STOX_TOKEN_OWNER_SAFE_OWNER_2";
        if (owner == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_3) return "STOX_TOKEN_OWNER_SAFE_OWNER_3";
        if (owner == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_4) return "STOX_TOKEN_OWNER_SAFE_OWNER_4";
        if (owner == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_5) return "STOX_TOKEN_OWNER_SAFE_OWNER_5";
        if (owner == LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_TDM) return "STOX_TOKEN_OWNER_SAFE_OWNER_TDM";
        revert UnnamedOwner(owner);
    }

    function roleName(bytes32 role) internal pure returns (string memory) {
        string[7] memory roles = [
            "DEPOSIT",
            "WITHDRAW",
            "CERTIFY",
            "CONFISCATE_SHARES",
            "CONFISCATE_RECEIPT",
            "SCHEDULE_CORPORATE_ACTION",
            "CANCEL_CORPORATE_ACTION"
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            if (role == keccak256(bytes(roles[i]))) return roles[i];
            string memory admin = string.concat(roles[i], "_ADMIN");
            if (role == keccak256(bytes(admin))) return admin;
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
        if (grantee == LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C) return "GRANTEE_SERVICE_3D0C";
        if (grantee == LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR) return "GRANTEE_ORCHESTRATOR";
        revert UnnamedGrantee(chainId, grantee);
    }

    function hex20(address a) internal pure returns (string memory) {
        return vm.toLowercase(vm.toString(a));
    }

    function pin(string memory pad, string memory name, address a) internal pure returns (string memory) {
        return string.concat(
            "{\n", pad, "  \"name\": \"", name, "\",\n", pad, "  \"address\": \"", hex20(a), "\"\n", pad, "}"
        );
    }

    function ownersJson() internal pure returns (string memory) {
        address[] memory owners = LibSafeInvariants.expectedOwners();
        string memory json = "[";
        for (uint256 i = 0; i < owners.length; i++) {
            json =
                string.concat(json, i == 0 ? "\n      " : ",\n      ", pin("      ", ownerName(owners[i]), owners[i]));
        }
        return string.concat(json, "\n    ]");
    }

    function grantsJson(uint256 chainId) internal pure returns (string memory) {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(
            LibSafeInvariants.safeForChainId(chainId), LibTimelockInvariants.timelockForChainId(chainId)
        );
        string memory json = "[";
        for (uint256 i = 0; i < grants.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "\n" : ",\n",
                "        {\n          \"role\": \"",
                vm.toString(grants[i].role),
                "\",\n          \"roleName\": \"",
                roleName(grants[i].role),
                "\",\n          \"grantee\": \"",
                hex20(grants[i].grantee),
                "\",\n          \"granteeName\": \"",
                granteeName(chainId, grants[i].grantee),
                "\"\n        }"
            );
        }
        return string.concat(json, "\n      ]");
    }

    function chainJson(uint256 chainId) internal pure returns (string memory) {
        string memory s = suffix(chainId);
        return string.concat(
            "    \"",
            vm.toString(chainId),
            "\": {\n      \"network\": \"",
            network(chainId),
            "\",\n      \"safe\": ",
            pin("      ", string.concat("STOX_TOKEN_OWNER_SAFE", s), LibSafeInvariants.safeForChainId(chainId)),
            ",\n      \"timelock\": ",
            pin(
                "      ",
                string.concat("STOX_GOVERNANCE_TIMELOCK", s),
                LibTimelockInvariants.timelockForChainId(chainId)
            ),
            ",\n      \"authoriser\": ",
            pin(
                "      ",
                string.concat("STOX_PROD_AUTHORISER_V4_CLONE", s),
                LibAuthoriserInvariants.authoriserForChainId(chainId)
            ),
            ",\n      \"authoriserGrants\": ",
            grantsJson(chainId),
            "\n    }"
        );
    }

    function render() public pure returns (string memory) {
        string memory out = string.concat(
            "{\n  \"version\": 1,\n  \"safePolicy\": {\n    \"threshold\": ",
            vm.toString(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD),
            ",\n    \"owners\": ",
            ownersJson(),
            "\n  },\n  \"authoriserImplementation\": ",
            pin(
                "  ",
                "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
            )
        );
        out = string.concat(
            out,
            ",\n  \"beaconOwners\": {\n    \"initial\": ",
            pin("    ", "BEACON_INITIAL_OWNER", LibProdDeployV4.BEACON_INITIAL_OWNER),
            ",\n    \"v2BaseReceipt\": ",
            pin("    ", "RECEIPT_BEACON_OWNER", LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER),
            ",\n    \"v2BaseVault\": ",
            pin("    ", "VAULT_BEACON_OWNER", LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER),
            "\n  },\n  \"chains\": {"
        );
        uint256[] memory ids = chainIds();
        for (uint256 i = 0; i < ids.length; i++) {
            out = string.concat(out, i == 0 ? "\n" : ",\n", chainJson(ids[i]));
        }
        return string.concat(out, "\n  }\n}\n");
    }

    function run() external {
        vm.writeFile(PATH, render());
    }
}
