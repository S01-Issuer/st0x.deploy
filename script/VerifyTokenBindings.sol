// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibProdTokenTargets} from "../src/lib/LibProdTokenTargets.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxTokenBindings} from "../src/lib/LibStoxTokenBindings.sol";

contract VerifyTokenBindings is Script {
    function run() external {
        LibStoxTokenBindings.checkOnNetworks(
            vm, LibStoxDeployNetworks.deploymentNetworks(), LibProdTokenTargets.vaultBeacon()
        );
    }
}
