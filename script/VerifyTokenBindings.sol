// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxTokenBindings} from "../src/lib/LibStoxTokenBindings.sol";

contract VerifyTokenBindings is StoxDeploySuites, Script {
    function run() external {
        LibStoxTokenBindings.checkOnNetworks(vm, LibStoxDeployNetworks.deploymentNetworks(), vaultBeacon());
    }
}
