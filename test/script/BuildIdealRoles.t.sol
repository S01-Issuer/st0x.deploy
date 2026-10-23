// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {BuildIdealRoles} from "../../script/BuildIdealRoles.sol";
import {LibIdealRoles, ContractRoles} from "../../src/lib/LibIdealRoles.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";

contract BuildIdealRolesTest is Test {
    BuildIdealRoles internal build = new BuildIdealRoles();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testChainsAreTheDeploymentNetworksKeyedByChainId() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".chains").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(vm.parseJsonString(json, string.concat(chain(nets[i]), ".network")), nets[i].name);
        }
    }

    function testContractsAreTheIdealRoleTargets() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            ContractRoles[] memory roles = LibIdealRoles.contractRoles(nets[c].chainId);
            string memory at = string.concat(chain(nets[c]), ".contracts");
            assertFalse(vm.keyExistsJson(json, index(at, roles.length)));
            for (uint256 i = 0; i < roles.length; i++) {
                assertEq(vm.parseJsonAddress(json, string.concat(index(at, i), ".address")), roles[i].target);
            }
        }
    }

    function testRowsAreTheExpectedPairs() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            ContractRoles[] memory roles = LibIdealRoles.contractRoles(nets[c].chainId);
            for (uint256 i = 0; i < roles.length; i++) {
                string memory at = string.concat(index(string.concat(chain(nets[c]), ".contracts"), i), ".expected");
                RoleGrant[] memory grants = roles[i].expected;
                assertFalse(vm.keyExistsJson(json, index(at, grants.length)));
                for (uint256 j = 0; j < grants.length; j++) {
                    assertEq(vm.parseJsonBytes32(json, string.concat(index(at, j), ".role")), grants[j].role);
                    assertEq(vm.parseJsonAddress(json, string.concat(index(at, j), ".grantee")), grants[j].grantee);
                }
            }
        }
    }

    function testRunWritesTheRender() external {
        vm.removeFile("ideal-roles.json");
        build.run();
        assertEq(keccak256(vm.parseJson(vm.readFile("ideal-roles.json"))), keccak256(vm.parseJson(build.render())));
    }

    function chain(SupportedNetwork memory network) internal pure returns (string memory) {
        return string.concat(".chains.", vm.toString(network.chainId));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }
}
