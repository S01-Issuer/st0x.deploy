// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {LibIdealRoles, ContractRoles} from "../src/lib/LibIdealRoles.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibRoleNames} from "../src/lib/LibRoleNames.sol";
import {RoleGrant} from "../src/lib/RoleGrant.sol";

/// @title BuildIdealRoles
/// @notice Writes `ideal-roles.json`: per deployment network, each contract's address and the pairs it must carry.
contract BuildIdealRoles is Script {
    string internal constant PATH = "ideal-roles.json";

    function grantsJson(string memory key, RoleGrant[] memory grants) internal returns (string[] memory) {
        string[] memory rows = new string[](grants.length);
        for (uint256 i = 0; i < grants.length; i++) {
            string memory row = string.concat(key, ".", vm.toString(i));
            vm.serializeBytes32(row, "role", grants[i].role);
            vm.serializeString(row, "roleName", LibRoleNames.nameOf(grants[i].role));
            rows[i] = vm.serializeAddress(row, "grantee", grants[i].grantee);
        }
        return rows;
    }

    function chainJson(SupportedNetwork memory network) internal returns (string memory) {
        ContractRoles[] memory roles = LibIdealRoles.contractRoles(network.chainId);
        string memory key = vm.toString(network.chainId);
        string[] memory contracts = new string[](roles.length);
        for (uint256 i = 0; i < roles.length; i++) {
            string memory contractKey = string.concat(key, ".", vm.toString(i));
            vm.serializeAddress(contractKey, "address", roles[i].target);
            string[] memory rows = grantsJson(contractKey, roles[i].expected);
            contracts[i] = vm.serializeString(contractKey, "expected", rows);
        }
        vm.serializeString(key, "network", network.name);
        return vm.serializeString(key, "contracts", contracts);
    }

    function render() public returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory chains;
        for (uint256 i = 0; i < networks.length; i++) {
            chains = vm.serializeString("chains", vm.toString(networks[i].chainId), chainJson(networks[i]));
        }
        vm.serializeUint("root", "version", 1);
        return vm.serializeString("root", "chains", chains);
    }

    function run() external {
        vm.writeJson(render(), PATH);
    }
}
