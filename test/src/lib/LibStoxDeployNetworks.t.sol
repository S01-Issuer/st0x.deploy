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
    /// ST0x deploys to Base only.
    function testSupportedNetworksIsBaseOnly() external pure {
        string[] memory networks = LibStoxDeployNetworks.supportedNetworks();
        assertEq(networks.length, 1, "expected exactly one deploy network");
        assertEq(networks[0], LibRainDeploy.BASE, "expected Base");
    }
}
