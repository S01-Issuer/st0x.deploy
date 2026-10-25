// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy, DeployDependency, SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibConfigRegistryDeploy.sol";
import {
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.22/src/generated/candidate/ConfigRegistry.sol";

import {StoxWrappedTokenVaultBeacon} from "../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_BEACON,
    BYTECODE_HASH as WRAPPED_BEACON_CODEHASH
} from "../src/generated/candidate/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_VAULT,
    RUNTIME_CODE as WRAPPED_VAULT_RUNTIME_CODE
} from "../src/generated/candidate/StoxWrappedTokenVault.pointers.sol";
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
/// @notice Deploys the wrapped-vault beacon to every network, owned by the
/// chain's bound beacon owner.
contract DeployBeacons is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
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

        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({
            deployedAddress: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE
        });
        dependencies[1] = DeployDependency({deployedAddress: WRAPPED_VAULT, runtimeCode: WRAPPED_VAULT_RUNTIME_CODE});

        bytes memory creationCode = type(StoxWrappedTokenVaultBeacon).creationCode;
        uint256[] memory forkIds = LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            msg.sender,
            boundZoltuDeployStep,
            LibRainDeploy.everyNetwork(
                networks.length, creationCode, WRAPPED_BEACON, LibRainDeploy.zoltuAddress(creationCode)
            ),
            WRAPPED_BEACON_CODEHASH,
            dependencies
        );
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertTimelockOwned(WRAPPED_BEACON);
        }
    }
}
