// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {LibCodeGen} from "rain.sol.codegen/lib/LibCodeGen.sol";
import {LibFs} from "rain.sol.codegen/lib/LibFs.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {StoxReceipt} from "../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxWrappedTokenVault} from "../src/concrete/StoxWrappedTokenVault.sol";
import {StoxUnifiedDeployer} from "../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";

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

    /// @notice Deploys a contract via the Zoltu factory and generates its
    /// pointer file containing `DEPLOYED_ADDRESS`, `CREATION_CODE`, and
    /// `RUNTIME_CODE` constants.
    /// @param name Must exactly match the contract's Solidity filename (without
    /// `.sol`), as it determines the generated pointer file path under
    /// `src/generated/`.
    /// @param creationCode The creation bytecode of the contract, typically
    /// obtained via `type(ContractName).creationCode`.
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

        // Corporate actions facet must be built BEFORE StoxReceiptVault because
        // the vault's `fallback()` override hardcodes the facet's deterministic
        // Zoltu address via `LibProdDeployV3`, which means the vault's creation
        // code depends on the facet's deploy address being fixed.
        buildContractPointers("StoxCorporateActionsFacet", type(StoxCorporateActionsFacet).creationCode);
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
        // Authorizers have no dependencies on other Stox contracts.
        buildContractPointers(
            "StoxOffchainAssetReceiptVaultAuthorizerV1", type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode
        );
        buildContractPointers(
            "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
            type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode
        );
    }
}
