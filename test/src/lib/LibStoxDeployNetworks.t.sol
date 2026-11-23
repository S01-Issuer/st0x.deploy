// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks, NotADeploymentNetwork} from "../../../src/lib/LibStoxDeployNetworks.sol";

/// @title LibStoxDeployNetworksTest
/// @notice Pins the ST0x deploy network set: the name constants so a rename
/// fails a test, and the one list both prod deploy scripts ship to.
contract LibStoxDeployNetworksTest is Test {
    /// The Ethereum network name is `rain-deploy`'s catalogue name, the
    /// foundry.toml rpc alias.
    function testEthereumNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.ETHEREUM, "ethereum", "expected ethereum rpc alias");
    }

    /// The HyperEVM network name is the foundry.toml rpc alias.
    function testHyperevmNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.HYPEREVM, "hyperevm", "expected hyperevm rpc alias");
    }

    /// The Robinhood Chain network name is the foundry.toml rpc alias.
    function testRobinhoodNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.ROBINHOOD, "robinhood", "expected robinhood rpc alias");
    }

    /// The BNB Smart Chain network name is the foundry.toml rpc alias.
    function testBscNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.BSC, "bsc", "expected bsc rpc alias");
    }

    /// The 0G network name is `rain-deploy`'s catalogue name.
    function testZerogNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.ZEROG, LibRainDeploy.ZEROG, "expected zerog rpc alias");
    }

    function testZerogIsRpcAlias() external view {
        assertGt(bytes(vm.rpcUrl(LibStoxDeployNetworks.ZEROG)).length, 0, LibStoxDeployNetworks.ZEROG);
    }

    /// The `zerog` alias forks 0G mainnet.
    function testZerogForksChain16661() external {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG);
        assertEq(block.chainid, 16661, LibStoxDeployNetworks.ZEROG);
    }

    /// The deploy list is exactly the six production chains, in a fixed
    /// order: the five before 0G, then 0G.
    function testDeploymentNetworks() external pure {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        assertEq(networks.length, 6, "expected six deploy networks");
        assertEq(networks[0], LibRainDeploy.BASE);
        assertEq(networks[1], LibStoxDeployNetworks.ETHEREUM);
        assertEq(networks[2], LibStoxDeployNetworks.HYPEREVM);
        assertEq(networks[3], LibStoxDeployNetworks.ROBINHOOD);
        assertEq(networks[4], LibStoxDeployNetworks.BSC);
        assertEq(networks[5], LibStoxDeployNetworks.ZEROG);
    }

    /// The networks before 0G are the deploy list without its last entry, 0G.
    function testNetworksBeforeZerogAreTheDeployListWithoutZerog() external pure {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        string[] memory before = LibStoxDeployNetworks.networksBeforeZerog();
        assertEq(before.length, networks.length - 1);
        for (uint256 i = 0; i < before.length; i++) {
            assertEq(before[i], networks[i]);
            assertNotEq(before[i], LibStoxDeployNetworks.ZEROG);
        }
    }

    /// Leaving out 0G keeps every other deployment network, in order.
    function testNetworksWithoutZerogAreEveryOtherDeploymentNetwork() external pure {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        string[] memory without = LibStoxDeployNetworks.networksWithout(LibStoxDeployNetworks.ZEROG);
        assertEq(without.length, networks.length - 1);
        uint256 j = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            if (keccak256(bytes(networks[i])) == keccak256(bytes(LibStoxDeployNetworks.ZEROG))) continue;
            assertEq(without[j++], networks[i]);
        }
    }

    /// Leaving out a network that is not in the deploy list leaves out nothing, so it is refused.
    function testNetworksWithoutAnUnknownNetworkIsRefused() external {
        vm.expectRevert(abi.encodeWithSelector(NotADeploymentNetwork.selector, "polygon"));
        this.networksWithout("polygon");
    }

    function networksWithout(string memory excluded) external pure returns (string[] memory) {
        return LibStoxDeployNetworks.networksWithout(excluded);
    }

    /// Every name in the deploy list resolves to a configured
    /// `[rpc_endpoints]` alias. `LibRainDeploy.deployToNetworks` passes each
    /// name straight to `vm.createSelectFork`, so a name that is not an alias
    /// is a dispatch-time failure that no constant-literal assertion catches.
    function testDeploymentNetworksAreRpcAliases() external view {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertGt(bytes(vm.rpcUrl(networks[i])).length, 0, networks[i]);
        }
    }
}
