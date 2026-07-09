// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.0/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.0/src/lib/LibFs.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
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
import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";

contract BuildPointers is Script {
    /// @notice The canonical release tag. Read from `foundry.toml`
    /// `[package].version` — the single source of truth — with dots converted
    /// to underscores for the Solidity constant/dir form (`0.1.3` -> `0_1_3`).
    /// Everything version-dependent (the `<tag>/` snapshot dir, `DEPLOY_TAG`,
    /// the current-release aliases) derives from this.
    function deployTag() internal view returns (string memory) {
        string memory version = vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version");
        bytes memory b = bytes(version);
        bytes memory out = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            out[i] = b[i] == "." ? bytes1("_") : b[i];
        }
        return string(out);
    }

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
    /// `src/generated/<tag>/` — the frozen per-release snapshot for the current
    /// `deployTag()` (read from the canonical `foundry.toml` version). Historical
    /// tags are never regenerated; a release bump writes a new `<tag>/` snapshot
    /// beside them.
    /// @param creationCode The creation bytecode of the contract, typically
    /// obtained via `type(ContractName).creationCode`.
    function buildContractPointers(string memory name, bytes memory creationCode) internal {
        address deployed = LibRainDeploy.deployZoltu(creationCode);

        LibFs.buildFileForContract(
            vm,
            deployed,
            string.concat(deployTag(), "/", name),
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

        // A fresh next-version slot has no `<tag>/` dir yet, and `vm.writeFile`
        // won't create one.
        vm.createDir(string.concat("src/generated/", deployTag()), true);

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
        // ST0x orchestrator. The beacon-set deployer's constructor bakes the
        // orchestrator impl constant, so the impl must be built (and thus
        // Zoltu-deployed at that address) before the deployer.
        buildContractPointers("ST0xOrchestrator", type(ST0xOrchestrator).creationCode);
        buildContractPointers("ST0xOrchestratorBeaconSetDeployer", type(ST0xOrchestratorBeaconSetDeployer).creationCode);
    }
}
