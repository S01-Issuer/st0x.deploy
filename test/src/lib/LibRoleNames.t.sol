// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRoleNames, UnnamedRole} from "../../../src/lib/LibRoleNames.sol";
import {LibIdealRoles, ContractRoles} from "../../../src/lib/LibIdealRoles.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";

contract LibRoleNamesTest is Test {
    function nameOf(bytes32 role) external pure returns (string memory) {
        return LibRoleNames.nameOf(role);
    }

    function testTheZeroRoleIsDefaultAdmin() external pure {
        assertEq(LibRoleNames.nameOf(bytes32(0)), "DEFAULT_ADMIN_ROLE");
    }

    function testANameIsThePreimageOfItsRole() external pure {
        assertEq(LibRoleNames.nameOf(keccak256("EMERGENCY")), "EMERGENCY");
        assertEq(LibRoleNames.nameOf(keccak256("PROPOSER_ROLE")), "PROPOSER_ROLE");
        assertEq(LibRoleNames.nameOf(keccak256("CANCEL_CORPORATE_ACTION_ADMIN")), "CANCEL_CORPORATE_ACTION_ADMIN");
    }

    function testAnUnknownRoleReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnnamedRole.selector, keccak256("NOT_A_ROLE")));
        this.nameOf(keccak256("NOT_A_ROLE"));
    }

    function testEveryExpectedRoleOnEveryNetworkIsNamed() external pure {
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 c = 0; c < nets.length; c++) {
            ContractRoles[] memory roles = LibIdealRoles.contractRoles(nets[c].chainId);
            for (uint256 i = 0; i < roles.length; i++) {
                for (uint256 j = 0; j < roles[i].expected.length; j++) {
                    bytes32 role = roles[i].expected[j].role;
                    string memory name = LibRoleNames.nameOf(role);
                    assertEq(role == bytes32(0) ? bytes32(0) : keccak256(bytes(name)), role, name);
                }
            }
        }
    }
}
