// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {Deploy} from "../../script/DeployProdV4_0_1_30.sol";
import {LibStoxDeployNetworks, UnknownDeploymentNetwork} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title DeployProdV4_0_1_30Test
/// @notice Network selection for the 0.1.30 orchestrator-set deploy script:
/// which networks one dispatch broadcasts to. Nothing here forks or
/// broadcasts — what the selection feeds (`LibRainDeploy.deployToNetworks`) is
/// upstream's.
contract DeployProdV4_0_1_30Test is Test {
    Deploy internal script;

    function setUp() external {
        script = new Deploy();
    }

    /// @dev The script resolves `DEPLOYMENT_NETWORK` through this same call.
    /// The selection is driven directly rather than through `vm.setEnv`
    /// because that mutates process environment which forge shares across
    /// concurrently running tests, and it is `external` because a revert
    /// inside an internal library call unwinds the test itself.
    /// @param selection The `DEPLOYMENT_NETWORK` value to resolve.
    /// @return The networks that value selects.
    function callSelectNetworks(string memory selection) external view returns (string[] memory) {
        return LibStoxDeployNetworks.selectNetworks(selection, script.supportedNetworks());
    }

    /// The vetted set the workflow's `network` choice mirrors, in the order the
    /// script broadcasts them.
    function testSupportedNetworks() external view {
        string[] memory supported = script.supportedNetworks();
        assertEq(supported.length, 3);
        assertEq(supported[0], LibRainDeploy.BASE);
        assertEq(supported[1], LibStoxDeployNetworks.ETHEREUM);
        assertEq(supported[2], LibStoxDeployNetworks.HYPEREVM);
    }

    /// The point of the sentinel: one dispatch, every supported network.
    function testAllSelectsEverySupportedNetwork() external view {
        string[] memory selected = this.callSelectNetworks(LibStoxDeployNetworks.ALL);
        string[] memory supported = script.supportedNetworks();
        assertEq(selected.length, supported.length);
        for (uint256 i = 0; i < supported.length; i++) {
            assertEq(selected[i], supported[i]);
        }
    }

    /// Per-network dispatch still ships to exactly one network.
    function testNamedNetworkSelectsOnlyItself() external view {
        string[] memory supported = script.supportedNetworks();
        for (uint256 i = 0; i < supported.length; i++) {
            string[] memory selected = this.callSelectNetworks(supported[i]);
            assertEq(selected.length, 1);
            assertEq(selected[0], supported[i]);
        }
    }

    /// A network this release does not ship to is rejected, not silently
    /// dropped from an otherwise-valid run.
    function testUnsupportedNetworkReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownDeploymentNetwork.selector, LibRainDeploy.POLYGON));
        this.callSelectNetworks(LibRainDeploy.POLYGON);
    }

    /// An unset `DEPLOYMENT_NETWORK` reaches the selection as the empty string,
    /// which reverts rather than defaulting to a chain — and in particular does
    /// not mean `all`.
    function testUnsetNetworkReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownDeploymentNetwork.selector, ""));
        this.callSelectNetworks("");
    }
}
