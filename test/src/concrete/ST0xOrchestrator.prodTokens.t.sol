// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibExtrospectRegistryBeaconProxy} from "rain-extrospection-0.1.16/src/lib/LibExtrospectRegistryBeaconProxy.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.13/src/interface/IReceiptVaultV3.sol";
import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

/// @notice Every production vault and receipt is bytecode the orchestrator
/// guard recognises as a registry beacon proxy, holding the chain's in-use
/// prod beacon.
contract ST0xOrchestratorProdTokensTest is Test {
    function assertProdTokensAreRegistryBeaconProxies(string memory network) internal {
        vm.createSelectFork(network);
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(block.chainid);
        assertTrue(tokens.length > 0, "no prod tokens");
        for (uint256 i = 0; i < tokens.length; i++) {
            address vault = tokens[i].receiptVault;
            (bool isProxy, address beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(vault.code);
            assertTrue(isProxy, string.concat(network, " vault not a registry beacon proxy: ", vm.toString(vault)));
            assertEq(beacon, beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], "vault beacon");

            address receipt = address(IReceiptVaultV3(payable(vault)).receipt());
            assertEq(receipt, tokens[i].receipt, "receipt");
            (isProxy, beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(receipt.code);
            assertTrue(isProxy, string.concat(network, " receipt not a registry beacon proxy: ", vm.toString(receipt)));
            assertEq(beacon, beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], "receipt beacon");
        }
    }

    function testBaseProdTokensAreRegistryBeaconProxies() external {
        assertProdTokensAreRegistryBeaconProxies(LibRainDeploy.BASE);
    }

    function testEthereumProdTokensAreRegistryBeaconProxies() external {
        assertProdTokensAreRegistryBeaconProxies(LibStoxDeployNetworks.ETHEREUM);
    }

    function testHyperEvmProdTokensAreRegistryBeaconProxies() external {
        assertProdTokensAreRegistryBeaconProxies(LibStoxDeployNetworks.HYPEREVM);
    }

    function testRobinhoodProdTokensAreRegistryBeaconProxies() external {
        assertProdTokensAreRegistryBeaconProxies(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testBscProdTokensAreRegistryBeaconProxies() external {
        assertProdTokensAreRegistryBeaconProxies(LibStoxDeployNetworks.BSC);
    }
}
