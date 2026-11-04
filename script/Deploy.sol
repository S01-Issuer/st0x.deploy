// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "rain-deploy-0.1.30/src/abstract/RainDeployBroadcast.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {
    LibOffchainAssetReceiptVaultRbac,
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
} from "rain-vats-0.2.18/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {StoxDeploySuites} from "../src/abstract/StoxDeploySuites.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "../src/lib/LibProdTokenTargets.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

error GovernanceSafeMismatch(address bound, address expected);
error GovernanceTimelockMismatch(address bound, address expected);
error VaultBeaconMismatch(address bound, address expected);
error ReceiptBeaconMismatch(address bound, address expected);
error RbacOwnerMismatch(bytes32 name, address bound, address expected);
error RbacAuthorizerMismatch(bytes32 name, address bound, address expected);

/// @title Deploy
/// @notice `RainDeployBroadcast` over `StoxDeploySuites`: broadcasts the suite
/// `DEPLOYMENT_SUITE` names to every network this repo deploys to. Before each
/// network it refuses unless every registry binding the suite's construction or
/// initialisation resolves is bound to this repo's pin for that chain; an
/// unbound name reverts in the registry.
contract Deploy is StoxDeploySuites, RainDeployBroadcast {
    function preDeployCheck(DeployDeclaration memory, DeploySuite memory suite, SupportedNetwork memory)
        internal
        view
        override
    {
        bytes32 name = keccak256(bytes(suite.suite));
        if (name == keccak256(bytes(GOVERNANCE_TIMELOCK))) {
            address bound = LibStoxConfig.governanceSafe();
            address expected = LibSafeInvariants.safeForChainId(block.chainid);
            if (bound != expected) {
                revert GovernanceSafeMismatch(bound, expected);
            }
        } else if (
            name == keccak256(bytes(RECEIPT_BEACON)) || name == keccak256(bytes(RECEIPT_VAULT_BEACON))
                || name == keccak256(bytes(WRAPPED_TOKEN_VAULT_BEACON))
        ) {
            address bound = LibStoxConfig.governanceTimelock();
            if (bound != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK) {
                revert GovernanceTimelockMismatch(bound, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
            }
        } else {
            TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
            for (uint256 i = 0; i < configs.length; i++) {
                if (name == keccak256(bytes(string.concat(TOKEN_PREFIX, lowercase(configs[i].symbol))))) {
                    checkToken(configs[i].region);
                    return;
                }
            }
        }
    }

    function checkToken(Region region) internal view {
        address vaultBeacon = boundAddress(LibStoxConfig.VAULT_BEACON_NAME);
        if (vaultBeacon != LibProdTokenTargets.vaultBeacon()) {
            revert VaultBeaconMismatch(vaultBeacon, LibProdTokenTargets.vaultBeacon());
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
            LibStoxConfig.ROOT_AUTHORITY, rbacName, OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
        );
        OffchainAssetReceiptVaultRbacV1 memory rbac =
            LibOffchainAssetReceiptVaultRbac.decodeCanonical(LibStoxConfig.ROOT_AUTHORITY, rbacName, value);
        if (rbac.owner != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK) {
            revert RbacOwnerMismatch(rbacName, rbac.owner, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        }
        if (address(rbac.authorizer) != expectedAuthorizer) {
            revert RbacAuthorizerMismatch(rbacName, address(rbac.authorizer), expectedAuthorizer);
        }
    }

    function boundAddress(bytes32 name) internal view returns (address) {
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(LibStoxConfig.ROOT_AUTHORITY, name, keccak256("address"));
        return abi.decode(value, (address));
    }
}
