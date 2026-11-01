// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V7_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V7_RUNTIME_CODE
} from "rain-factory-deploy-0.2.4/src/generated/0_2_4/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibStoxTokenGaps} from "../src/lib/LibStoxTokenGaps.sol";
import {LibStoxVaultBeacon} from "../src/generated/LibStoxVaultBeacon.sol";

contract FillTokenGaps is StoxDeploySuites, Script {
    function run() external {
        string memory network = vm.envString("NETWORK");
        checkPins(network);
        LibStoxTokenGaps.fill(vm, network, msg.sender, tokenTargets());
    }

    function check() external view {
        string memory network = vm.envString("NETWORK");
        checkPins(network);
        LibStoxTokenGaps.check(network, tokenTargets());
    }

    function checkPins(string memory network) internal view {
        LibStoxTokenGaps.checkPin(network, CLONE_FACTORY_V7_ADDRESS, CLONE_FACTORY_V7_RUNTIME_CODE);
        LibStoxTokenGaps.checkPin(network, CONFIG_REGISTRY_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE);
        LibStoxTokenGaps.checkPin(network, vaultBeacon(), LibStoxVaultBeacon.RUNTIME_CODE);
    }
}
