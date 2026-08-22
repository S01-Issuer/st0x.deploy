// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";

/// @title LibStoxDeployNetworksTest
/// @notice Pins the ST0x-specific deploy network-name constants so a rename
/// fails a test.
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
}
