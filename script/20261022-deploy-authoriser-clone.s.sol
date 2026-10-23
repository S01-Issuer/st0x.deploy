// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {ICloneableFactoryV5} from "rain-factory-0.2.4/src/interface/ICloneableFactoryV5.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.1/src/generated/0_2_1/CloneFactory.sol";
import {LibRainDeploy, DeployDependency, SupportedNetwork} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.21/src/lib/LibConfigRegistryDeploy.sol";
import {
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.21/src/generated/candidate/ConfigRegistry.sol";

import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    DEPLOYED_ADDRESS as AUTHORISER,
    BYTECODE_HASH as AUTHORISER_CODEHASH,
    RUNTIME_CODE as AUTHORISER_RUNTIME_CODE
} from "../src/generated/candidate/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {AUTHORISER_CLONE_SALT, LibAuthoriserClone} from "../src/lib/LibAuthoriserClone.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The chain's bound authoriser admin is not its governance timelock.
/// @param network The network.
/// @param admin The bound admin.
error AuthoriserAdminNotTimelock(string network, address admin);

/// @notice Reverts unless the selected fork binds the authoriser admin to its
/// governance timelock; `LibStoxConfig.authoriserAdmin` reverts where unbound.
/// @param network The network, for the refusal to name.
function requireAdminBound(string memory network) view {
    address admin = LibStoxConfig.authoriserAdmin();
    if (admin != LibTimelockInvariants.timelockForChainId(block.chainid)) {
        revert AuthoriserAdminNotTimelock(network, admin);
    }
}

/// @notice The Zoltu step, refused where the admin is not bound.
/// @param vm The cheatcode handle.
/// @param network The network.
/// @param deployer The broadcaster.
/// @param creationCode The creation code.
/// @return The deployed address.
function boundZoltuDeployStep(Vm vm, string memory network, address deployer, bytes memory creationCode)
    returns (address)
{
    requireAdminBound(network);
    return LibRainDeploy.zoltuDeployStep(vm, network, deployer, creationCode);
}

/// @notice The clone step, refused where the admin is not bound.
/// @param vm The cheatcode handle.
/// @param network The network.
/// @param deployer The broadcaster.
/// @param data The init data.
/// @return The clone.
function boundCloneStep(Vm vm, string memory network, address deployer, bytes memory data) returns (address) {
    requireAdminBound(network);
    vm.startBroadcast(deployer);
    address clone =
        ICloneableFactoryV5(CLONE_FACTORY).cloneDeterministicOpenSalt(AUTHORISER, data, AUTHORISER_CLONE_SALT);
    vm.stopBroadcast();
    return clone;
}

/// @title DeployAuthoriserClone
/// @notice Deploys the candidate authoriser and its open-salt clone to every
/// network. The clone's admin is the chain's bound `AUTHORISER_ADMIN`, so one
/// address serves every chain. Idempotent: a network already holding either
/// is skipped.
contract DeployAuthoriserClone is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @notice Reverts unless `clone` carries the timelock's `_ADMIN`
    /// roles and no deploy key holds any role.
    /// @param clone The clone.
    function assertCloneState(address clone) internal view {
        LibAuthoriserInvariants.assertAdminRolesHeld(clone, LibTimelockInvariants.timelockForChainId(block.chainid));
        LibAuthoriserInvariants.assertKeysHoldNoRoles(clone);
    }

    function run() external {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());

        bytes memory creationCode = type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode;
        LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            msg.sender,
            boundZoltuDeployStep,
            LibRainDeploy.everyNetwork(
                networks.length, creationCode, AUTHORISER, LibRainDeploy.zoltuAddress(creationCode)
            ),
            AUTHORISER_CODEHASH,
            new DeployDependency[](0)
        );

        DeployDependency[] memory dependencies = new DeployDependency[](3);
        dependencies[0] = DeployDependency({
            deployedAddress: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE
        });
        dependencies[1] = DeployDependency({deployedAddress: CLONE_FACTORY, runtimeCode: CLONE_FACTORY_RUNTIME_CODE});
        dependencies[2] = DeployDependency({deployedAddress: AUTHORISER, runtimeCode: AUTHORISER_RUNTIME_CODE});
        uint256[] memory forkIds = LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            msg.sender,
            boundCloneStep,
            LibRainDeploy.everyNetwork(
                networks.length,
                LibAuthoriserClone.cloneData(),
                LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE,
                LibAuthoriserClone.cloneDeployedAddress(AUTHORISER)
            ),
            LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE_CODEHASH,
            dependencies
        );
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertCloneState(LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE);
        }
    }
}
