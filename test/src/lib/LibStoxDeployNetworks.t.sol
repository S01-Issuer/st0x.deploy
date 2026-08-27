// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";

/// @title LibStoxDeployNetworksTest
/// @notice Pins the ST0x deploy network set: the name constants so a rename
/// fails a test, and the one list both prod deploy scripts ship to.
contract LibStoxDeployNetworksTest is Test {
    /// The locally-declared Ethereum network name matches the foundry.toml rpc
    /// alias convention used by every LibRainDeploy constant.
    function testEthereumNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.ETHEREUM, "ethereum", "expected ethereum rpc alias");
    }

    /// The locally-declared HyperEVM network name matches the foundry.toml rpc
    /// alias convention.
    function testHyperevmNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.HYPEREVM, "hyperevm", "expected hyperevm rpc alias");
    }

    /// The deploy list is exactly the three production chains, in a fixed
    /// order. Both `DeployProdV4_0_1_1` and `DeployProdV4_0_1_30` hand this
    /// whole list to `LibRainDeploy.deployAndBroadcast`, so a network dropped
    /// here silently stops being deployed to.
    function testDeploymentNetworks() external pure {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        assertEq(networks.length, 3, "expected three deploy networks");
        assertEq(networks[0], LibRainDeploy.BASE);
        assertEq(networks[1], LibStoxDeployNetworks.ETHEREUM);
        assertEq(networks[2], LibStoxDeployNetworks.HYPEREVM);
    }

    /// Every name in the deploy list resolves to a configured
    /// `[rpc_endpoints]` alias. `LibRainDeploy.deployToNetworks` passes each
    /// name straight to `vm.createSelectFork`, so a name that is not an alias
    /// is a dispatch-time failure that no constant-literal assertion catches.
    function testDeploymentNetworksAreRpcAliases() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertGt(bytes(vm.rpcUrl(networks[i])).length, 0, networks[i]);
        }
    }
}
