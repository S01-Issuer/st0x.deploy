// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibIdealRoles, ContractRoles} from "../src/lib/LibIdealRoles.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {RoleGrant} from "../src/lib/RoleGrant.sol";

/// @title BuildIdealRoles
/// @notice Writes `ideal-roles.json`: per deployment network, each contract's address and the pairs it must carry.
contract BuildIdealRoles is Script {
    string internal constant PATH = "ideal-roles.json";

    function hex20(address a) internal pure returns (string memory) {
        return vm.toLowercase(vm.toString(a));
    }

    function grantsJson(RoleGrant[] memory grants) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < grants.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "\n" : ",\n",
                "            {\n              \"role\": \"",
                vm.toString(grants[i].role),
                "\",\n              \"grantee\": \"",
                hex20(grants[i].grantee),
                "\"\n            }"
            );
        }
        return string.concat(json, grants.length == 0 ? "]" : "\n          ]");
    }

    function chainJson(SupportedNetwork memory network) internal pure returns (string memory) {
        ContractRoles[] memory roles = LibIdealRoles.contractRoles(network.chainId);
        string memory json = string.concat(
            "    \"",
            vm.toString(network.chainId),
            "\": {\n      \"network\": \"",
            network.name,
            "\",\n      \"contracts\": ["
        );
        for (uint256 i = 0; i < roles.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "\n" : ",\n",
                "        {\n          \"address\": \"",
                hex20(roles[i].target),
                "\",\n          \"expected\": ",
                grantsJson(roles[i].expected),
                "\n        }"
            );
        }
        return string.concat(json, "\n      ]\n    }");
    }

    function render() public pure returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory out = "{\n  \"version\": 1,\n  \"chains\": {";
        for (uint256 i = 0; i < networks.length; i++) {
            out = string.concat(out, i == 0 ? "\n" : ",\n", chainJson(networks[i]));
        }
        return string.concat(out, "\n  }\n}\n");
    }

    function run() external {
        vm.writeFile(PATH, render());
    }
}
