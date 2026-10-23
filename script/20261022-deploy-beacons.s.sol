// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy, DeployDependency, SupportedNetwork} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibConfigRegistryDeploy.sol";
import {
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.21/src/generated/candidate/ConfigRegistry.sol";

import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_BEACON,
    BYTECODE_HASH as WRAPPED_BEACON_CODEHASH
} from "../src/generated/candidate/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    DEPLOYED_ADDRESS as OARV_DEPLOYER,
    BYTECODE_HASH as OARV_DEPLOYER_CODEHASH
} from "../src/generated/candidate/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";
import {
    DEPLOYED_ADDRESS as ORCHESTRATOR_DEPLOYER,
    BYTECODE_HASH as ORCHESTRATOR_DEPLOYER_CODEHASH
} from "../src/generated/candidate/ST0xOrchestratorBeaconSetDeployer.pointers.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_VAULT,
    RUNTIME_CODE as WRAPPED_VAULT_RUNTIME_CODE
} from "../src/generated/candidate/StoxWrappedTokenVault.pointers.sol";
import {
    DEPLOYED_ADDRESS as RECEIPT,
    RUNTIME_CODE as RECEIPT_RUNTIME_CODE
} from "../src/generated/candidate/StoxReceipt.pointers.sol";
import {
    DEPLOYED_ADDRESS as RECEIPT_VAULT,
    RUNTIME_CODE as RECEIPT_VAULT_RUNTIME_CODE
} from "../src/generated/candidate/StoxReceiptVault.pointers.sol";
import {
    DEPLOYED_ADDRESS as ORCHESTRATOR,
    RUNTIME_CODE as ORCHESTRATOR_RUNTIME_CODE
} from "../src/generated/candidate/ST0xOrchestrator.pointers.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice A deployed beacon is not owned by the chain's timelock.
/// @param beacon The beacon.
/// @param owner Its owner.
error BeaconOwnerNotTimelock(address beacon, address owner);

/// @notice The Zoltu step, refused where the beacon owner is unbound.
/// @param vm The cheatcode handle.
/// @param network The network.
/// @param deployer The broadcaster.
/// @param creationCode The creation code.
/// @return The deployed address.
function boundZoltuDeployStep(Vm vm, string memory network, address deployer, bytes memory creationCode)
    returns (address)
{
    LibStoxConfig.beaconOwner();
    return LibRainDeploy.zoltuDeployStep(vm, network, deployer, creationCode);
}

/// @title DeployBeacons
/// @notice Deploys the wrapped-vault beacon and the OARV and orchestrator
/// beacon-set deployers to every network, each owned by the chain's bound
/// beacon owner.
contract DeployBeacons is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @notice Deploys `creationCode` to `expected` on every network.
    function deployEverywhere(
        SupportedNetwork[] memory networks,
        bytes memory creationCode,
        address expected,
        bytes32 codeHash,
        DeployDependency[] memory dependencies
    ) internal returns (uint256[] memory) {
        return LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            msg.sender,
            boundZoltuDeployStep,
            LibRainDeploy.everyNetwork(
                networks.length, creationCode, expected, LibRainDeploy.zoltuAddress(creationCode)
            ),
            codeHash,
            dependencies
        );
    }

    /// @notice The registry and `implementation`.
    function dependsOn(address implementation, bytes memory runtimeCode)
        internal
        pure
        returns (DeployDependency[] memory)
    {
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({
            deployedAddress: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE
        });
        dependencies[1] = DeployDependency({deployedAddress: implementation, runtimeCode: runtimeCode});
        return dependencies;
    }

    /// @notice Reverts unless `beacon` is owned by the active chain's timelock.
    function assertTimelockOwned(address beacon) internal view {
        address owner = Ownable(beacon).owner();
        if (owner != LibTimelockInvariants.timelockForChainId(block.chainid)) {
            revert BeaconOwnerNotTimelock(beacon, owner);
        }
    }

    function run() external {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());

        uint256[] memory forkIds = deployEverywhere(
            networks,
            type(StoxWrappedTokenVaultBeacon).creationCode,
            WRAPPED_BEACON,
            WRAPPED_BEACON_CODEHASH,
            dependsOn(WRAPPED_VAULT, WRAPPED_VAULT_RUNTIME_CODE)
        );
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertTimelockOwned(WRAPPED_BEACON);
        }

        DeployDependency[] memory oarvDependencies = new DeployDependency[](3);
        DeployDependency[] memory receiptDependencies = dependsOn(RECEIPT, RECEIPT_RUNTIME_CODE);
        oarvDependencies[0] = receiptDependencies[0];
        oarvDependencies[1] = receiptDependencies[1];
        oarvDependencies[2] =
            DeployDependency({deployedAddress: RECEIPT_VAULT, runtimeCode: RECEIPT_VAULT_RUNTIME_CODE});
        forkIds = deployEverywhere(
            networks,
            type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode,
            OARV_DEPLOYER,
            OARV_DEPLOYER_CODEHASH,
            oarvDependencies
        );
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            StoxOffchainAssetReceiptVaultBeaconSetDeployer oarv =
                StoxOffchainAssetReceiptVaultBeaconSetDeployer(OARV_DEPLOYER);
            assertTimelockOwned(address(oarv.iReceiptBeacon()));
            assertTimelockOwned(address(oarv.iOffchainAssetReceiptVaultBeacon()));
        }

        forkIds = deployEverywhere(
            networks,
            type(ST0xOrchestratorBeaconSetDeployer).creationCode,
            ORCHESTRATOR_DEPLOYER,
            ORCHESTRATOR_DEPLOYER_CODEHASH,
            dependsOn(ORCHESTRATOR, ORCHESTRATOR_RUNTIME_CODE)
        );
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertTimelockOwned(address(ST0xOrchestratorBeaconSetDeployer(ORCHESTRATOR_DEPLOYER).iOrchestratorBeacon()));
        }
    }
}
