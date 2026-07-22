// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibStoxDeployNetworksTest
/// @notice Pins the ST0x deploy network set so any change to the supported
/// networks fails a test.
contract LibStoxDeployNetworksTest is Test {
    /// ST0x deploys to Base + Ethereum mainnet, in that order (Base first as
    /// the reference network carrying the live production state).
    function testSupportedNetworksIsBaseAndEthereum() external pure {
        string[] memory networks = LibStoxDeployNetworks.supportedNetworks();
        assertEq(networks.length, 2, "expected exactly two deploy networks");
        assertEq(networks[0], LibRainDeploy.BASE, "expected Base first");
        assertEq(networks[1], LibStoxDeployNetworks.ETHEREUM, "expected Ethereum second");
    }

    /// The locally-declared Ethereum network name matches the foundry.toml
    /// rpc alias convention used by every LibRainDeploy constant.
    function testEthereumNetworkName() external pure {
        assertEq(LibStoxDeployNetworks.ETHEREUM, "ethereum", "expected ethereum rpc alias");
    }
}
