// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {LibCodeGen} from "rain.sol.codegen/lib/LibCodeGen.sol";
import {LibFs} from "rain.sol.codegen/lib/LibFs.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {StoxReceipt} from "../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../src/concrete/StoxWrappedTokenVault.sol";
import {StoxUnifiedDeployer} from "../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";

contract BuildPointers is Script {
    function addressConstantString(address addr) internal pure returns (string memory) {
        return string.concat(
            "\n",
            "/// @dev The deterministic deploy address of the contract when deployed via\n",
            "/// the Zoltu factory.\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(addr),
            ");\n"
        );
    }

    function buildContractPointers(string memory name, bytes memory creationCode) internal {
        address deployed = LibRainDeploy.deployZoltu(creationCode);

        LibFs.buildFileForContract(
            vm,
            deployed,
            name,
            string.concat(
                addressConstantString(deployed),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", creationCode
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed.code
                )
            )
        );
    }

    function run() external {
        LibRainDeploy.etchZoltuFactory(vm);

        buildContractPointers("StoxReceipt", type(StoxReceipt).creationCode);
        buildContractPointers("StoxReceiptVault", type(StoxReceiptVault).creationCode);
        buildContractPointers("StoxWrappedTokenVault", type(StoxWrappedTokenVault).creationCode);
        // Beacon must be built before the deployer since the deployer imports
        // the beacon's pointer file.
        buildContractPointers("StoxWrappedTokenVaultBeacon", type(StoxWrappedTokenVaultBeacon).creationCode);
        buildContractPointers(
            "StoxWrappedTokenVaultBeaconSetDeployer", type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode
        );
        // OARV deployer depends on StoxReceipt and StoxReceiptVault pointers.
        buildContractPointers(
            "StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode
        );
        buildContractPointers("StoxUnifiedDeployer", type(StoxUnifiedDeployer).creationCode);
    }
}
