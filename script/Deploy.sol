// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "rain-deploy-0.1.30/src/abstract/RainDeployBroadcast.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {
    LibOffchainAssetReceiptVaultRbac,
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
} from "rain-vats-0.2.20/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../src/lib/LibProdTokenParams.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {BeaconImplementationMismatch} from "../src/lib/LibBeaconInvariants.sol";

error TimelockInitialProposerMismatch(address bound, address expected);
error BeaconInitialOwnerMismatch(address bound, address expected);
error VaultBeaconMismatch(address bound, address expected);
error ReceiptBeaconMismatch(address bound, address expected);
error WrapperBeaconMismatch(address bound, address expected);
error VaultBeaconNotDeployed(address beacon);
error RbacOwnerMismatch(bytes32 name, address bound, address expected);
error RbacAuthorizerMismatch(bytes32 name, address bound, address expected);

/// @title Deploy
/// @notice `RainDeployBroadcast` over `StoxDeploySuites`: broadcasts the suite
/// `DEPLOYMENT_SUITE` names to every network this repo deploys to. Before each
/// network it refuses unless every registry binding the suite's construction or
/// initialisation resolves is bound to this repo's pin for that chain (an
/// unbound name reverts in the registry), and, for beacon and token suites,
/// unless the governance timelock that owns them is in its pinned state.
contract Deploy is StoxDeploySuites, RainDeployBroadcast {
    function preDeployCheck(DeployDeclaration memory, DeploySuite memory suite, SupportedNetwork memory)
        internal
        view
        override
    {
        bytes32 name = keccak256(bytes(suite.suite));
        if (name == keccak256(bytes(GOVERNANCE_TIMELOCK))) {
            address bound = LibStoxConfig.timelockInitialProposer();
            address expected = LibSafeInvariants.safeForChainId(block.chainid);
            if (bound != expected) {
                revert TimelockInitialProposerMismatch(bound, expected);
            }
        } else if (
            name == keccak256(bytes(RECEIPT_BEACON)) || name == keccak256(bytes(RECEIPT_VAULT_BEACON))
                || name == keccak256(bytes(WRAPPED_TOKEN_VAULT_BEACON)) || name == keccak256(bytes(ORCHESTRATOR_BEACON))
        ) {
            address bound = LibStoxConfig.beaconInitialOwner();
            if (bound != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK) {
                revert BeaconInitialOwnerMismatch(bound, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
            }
            checkGovernanceTimelock();
        } else {
            checkTokenSuites(name, tokenConfigs());
            checkTokenSuites(name, LibProdTokenConfig.testTokenConfigs());
        }
    }

    function checkTokenSuites(bytes32 name, TokenConfig[] memory configs) internal view {
        for (uint256 i = 0; i < configs.length; i++) {
            string memory token = string.concat(TOKEN_PREFIX, lowercase(configs[i].symbol));
            if (name == keccak256(bytes(token))) {
                checkToken(configs[i].region);
                return;
            }
            if (name == keccak256(bytes(string.concat(token, WRAPPER_SUFFIX)))) {
                checkWrapper();
                return;
            }
        }
    }

    function checkWrapper() internal view {
        address wrapperBeacon = boundAddress(LibStoxConfig.WRAPPER_BEACON_NAME);
        if (wrapperBeacon != LibProdTokenParams.wrapperBeacon()) {
            revert WrapperBeaconMismatch(wrapperBeacon, LibProdTokenParams.wrapperBeacon());
        }
    }

    function checkToken(Region region) internal view {
        address vaultBeacon = boundAddress(LibStoxConfig.VAULT_BEACON_NAME);
        if (vaultBeacon != LibProdTokenParams.vaultBeacon()) {
            revert VaultBeaconMismatch(vaultBeacon, LibProdTokenParams.vaultBeacon());
        }
        // A token's address commits to the beacon name, so the beacon must serve the hook-carrying implementation.
        if (vaultBeacon.code.length == 0) revert VaultBeaconNotDeployed(vaultBeacon);
        address implementation = IBeacon(vaultBeacon).implementation();
        if (implementation != LibProdDeployCurrent.STOX_RECEIPT_VAULT) {
            revert BeaconImplementationMismatch(vaultBeacon, LibProdDeployCurrent.STOX_RECEIPT_VAULT, implementation);
        }
        address receiptBeacon = boundAddress(LibStoxConfig.RECEIPT_BEACON_NAME);
        if (receiptBeacon != LibProdDeployCurrent.STOX_RECEIPT_BEACON) {
            revert ReceiptBeaconMismatch(receiptBeacon, LibProdDeployCurrent.STOX_RECEIPT_BEACON);
        }
        bytes32 rbacName = region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME;
        address expectedAuthorizer = region == Region.US
            ? LibAuthoriserInvariants.authoriserForChainId(block.chainid)
            : LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(
            LibRegistryAuthority.ROOT_AUTHORITY, rbacName, OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
        );
        OffchainAssetReceiptVaultRbacV1 memory rbac =
            LibOffchainAssetReceiptVaultRbac.decodeCanonical(LibRegistryAuthority.ROOT_AUTHORITY, rbacName, value);
        if (rbac.owner != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK) {
            revert RbacOwnerMismatch(rbacName, rbac.owner, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        }
        if (address(rbac.authorizer) != expectedAuthorizer) {
            revert RbacAuthorizerMismatch(rbacName, address(rbac.authorizer), expectedAuthorizer);
        }
        checkGovernanceTimelock();
    }

    /// @notice Reverts unless the governance timelock that owns the beacons and token RBACs has its pinned code,
    /// delay and roles, with the chain's pinned Safe address as proposer; the Safe's own policy is not checked here.
    function checkGovernanceTimelock() internal view {
        LibTimelockInvariants.assertTimelockState(
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, LibSafeInvariants.safeForChainId(block.chainid)
        );
    }

    function boundAddress(bytes32 name) internal view returns (address) {
        // slither-disable-next-line unused-return
        (bytes memory value,) =
            LibConfigRegistry.resolve(LibRegistryAuthority.ROOT_AUTHORITY, name, keccak256("address"));
        return abi.decode(value, (address));
    }
}
