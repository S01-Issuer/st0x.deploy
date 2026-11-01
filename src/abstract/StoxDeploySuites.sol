// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "rain-deploy-0.1.29/src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "rain-deploy-0.1.29/src/lib/LibRainDeployZoltuMechanism.sol";
import {CloneDeploy} from "rain-factory-0.2.7/src/lib/LibRainDeployClone.sol";
import {LibCloneCandidates} from "rain-factory-0.2.7/src/lib/LibCloneCandidates.sol";
import {LibRainDeployCloneMechanism} from "rain-factory-0.2.7/src/lib/LibRainDeployCloneMechanism.sol";
import {RegistryBeaconProxyDeploy} from "rain-factory-0.2.7/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V7_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V7_RUNTIME_CODE
} from "rain-factory-deploy-0.2.4/src/generated/0_2_4/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.13/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.4/src/generated/0_1_15/CloneFactory.sol";

import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    RUNTIME_CODE as TOFU_DECIMALS_RUNTIME_CODE
} from "rain-tofu-erc20-decimals-deploy-0.1.4/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {EU_AUTHORISER_SALT, LibEuAuthoriserClone} from "../lib/LibEuAuthoriserClone.sol";
import {LibStoxDeployNetworks} from "../lib/LibStoxDeployNetworks.sol";
import {LibReleasedSuites} from "../lib/LibReleasedSuites.sol";
import {LibStoxConfig} from "../lib/LibStoxConfig.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../lib/LibProdTokenConfig.sol";
import {LibStoxTokenProxies} from "../generated/LibStoxTokenProxies.sol";

/// @title StoxDeploySuites
/// @notice Every deterministic deployment this repo makes, declared once for
/// the deploy script and the verification tests. Released suites alias the
/// frozen `src/generated/<tag>/` record; candidates alias `candidate/`.
///
/// Suite keys are the `manual-sol-artifacts.yaml` dispatch choices.
abstract contract StoxDeploySuites is RainDeploySuitesBase {
    string constant FACET = "stox-corporate-actions-facet";
    string constant RECEIPT = "stox-receipt";
    string constant RECEIPT_VAULT = "stox-receipt-vault";
    string constant WRAPPED_TOKEN_VAULT = "stox-wrapped-token-vault";
    string constant WRAPPED_TOKEN_VAULT_BEACON = "stox-wrapped-token-vault-beacon";
    string constant AUTHORIZER = "stox-offchain-asset-receipt-vault-authorizer";
    string constant PAYMENT_MINT_AUTHORIZER = "stox-offchain-asset-receipt-vault-payment-mint-authorizer";
    string constant ORCHESTRATOR = "stox-orchestrator";
    string constant EU_AUTHORISER = "stox-eu-assets-authoriser";
    string constant UNIFIED_DEPLOYER = "stox-unified-deployer";
    string constant WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = "stox-wrapped-token-vault-beacon-set-deployer";
    string constant RECEIPT_VAULT_BEACON_SET_DEPLOYER = "stox-offchain-asset-receipt-vault-beacon-set-deployer";
    string constant ORCHESTRATOR_BEACON_SET_DEPLOYER = "stox-orchestrator-beacon-set-deployer";

    string constant FACET_PATH = "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet";
    string constant RECEIPT_PATH = "src/concrete/StoxReceipt.sol:StoxReceipt";
    string constant RECEIPT_VAULT_PATH = "src/concrete/StoxReceiptVault.sol:StoxReceiptVault";
    string constant WRAPPED_TOKEN_VAULT_PATH = "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault";
    string constant WRAPPED_TOKEN_VAULT_BEACON_PATH =
        "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon";
    string constant AUTHORIZER_PATH =
        "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol:StoxOffchainAssetReceiptVaultAuthorizerV1";
    string constant PAYMENT_MINT_AUTHORIZER_PATH =
        "src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol:StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1";
    string constant ORCHESTRATOR_PATH = "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator";
    string constant UNIFIED_DEPLOYER_PATH = "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer";
    string constant WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_PATH =
        "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer";
    string constant RECEIPT_VAULT_BEACON_SET_DEPLOYER_PATH =
        "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer";
    string constant ORCHESTRATOR_BEACON_SET_DEPLOYER_PATH =
        "src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol:ST0xOrchestratorBeaconSetDeployer";

    /// @inheritdoc RainDeploySuitesBase
    function declaration() internal view virtual override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared;
        LibRainDeployDeclaration.extend(declared);
        LibRainDeployDeclaration.setNetworks(declared, LibStoxDeployNetworks.deploymentNetworks());
        LibRainDeployZoltuMechanism.extend(declared);
        LibRainDeployCloneMechanism.extend(declared);
        LibRainDeployDeclaration.addReleased(declared, LibReleasedSuites.releasedSuites());
        LibRainDeployDeclaration.addCandidates(declared, candidateSuites());
        LibCloneCandidates.addClones(declared, euAuthoriserClones());
        LibCloneCandidates.addRegistryBeaconProxies(declared, tokenSuites());
        return declared;
    }

    function candidateSuites() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](8);
        candidates[0] = anchored(
            zoltu(
                FACET,
                V4.STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_CANDIDATE,
                V4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
                V4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_CANDIDATE,
                V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_CANDIDATE,
                FACET_PATH,
                one(TOFU_DECIMALS_ADDRESS, TOFU_DECIMALS_RUNTIME_CODE)
            )
        );
        candidates[1] = anchored(
            zoltu(
                RECEIPT,
                V4.STOX_RECEIPT_CREATION_CODE_CANDIDATE,
                V4.STOX_RECEIPT_CANDIDATE,
                V4.STOX_RECEIPT_CODEHASH_CANDIDATE,
                V4.STOX_RECEIPT_RUNTIME_CODE_CANDIDATE,
                RECEIPT_PATH,
                new DeployDependency[](0)
            )
        );
        candidates[2] = anchored(
            zoltu(
                RECEIPT_VAULT,
                V4.STOX_RECEIPT_VAULT_CREATION_CODE_CANDIDATE,
                V4.STOX_RECEIPT_VAULT_CANDIDATE,
                V4.STOX_RECEIPT_VAULT_CODEHASH_CANDIDATE,
                V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_CANDIDATE,
                RECEIPT_VAULT_PATH,
                one(V4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_CANDIDATE)
            )
        );
        candidates[3] = anchored(
            zoltu(
                WRAPPED_TOKEN_VAULT,
                V4.STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE_CANDIDATE,
                V4.STOX_WRAPPED_TOKEN_VAULT_CANDIDATE,
                V4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_CANDIDATE,
                V4.STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_CANDIDATE,
                WRAPPED_TOKEN_VAULT_PATH,
                new DeployDependency[](0)
            )
        );
        candidates[4] = anchored(
            zoltu(
                WRAPPED_TOKEN_VAULT_BEACON,
                V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_CANDIDATE,
                V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE,
                V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_CANDIDATE,
                V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_CANDIDATE,
                WRAPPED_TOKEN_VAULT_BEACON_PATH,
                one(V4.STOX_WRAPPED_TOKEN_VAULT_CANDIDATE, V4.STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_CANDIDATE)
            )
        );
        candidates[5] = anchored(
            zoltu(
                AUTHORIZER,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_CODE_CANDIDATE,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CANDIDATE,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_CANDIDATE,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_CODE_CANDIDATE,
                AUTHORIZER_PATH,
                new DeployDependency[](0)
            )
        );
        candidates[6] = anchored(
            zoltu(
                PAYMENT_MINT_AUTHORIZER,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_CODE_CANDIDATE,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CANDIDATE,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_CANDIDATE,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE_CANDIDATE,
                PAYMENT_MINT_AUTHORIZER_PATH,
                new DeployDependency[](0)
            )
        );
        candidates[7] = anchored(
            zoltu(
                ORCHESTRATOR,
                V4.ST0X_ORCHESTRATOR_CREATION_CODE_CANDIDATE,
                V4.ST0X_ORCHESTRATOR_CANDIDATE,
                V4.ST0X_ORCHESTRATOR_CODEHASH_CANDIDATE,
                V4.ST0X_ORCHESTRATOR_RUNTIME_CODE_CANDIDATE,
                ORCHESTRATOR_PATH,
                two(
                    V4.STOX_RECEIPT_CANDIDATE,
                    V4.STOX_RECEIPT_RUNTIME_CODE_CANDIDATE,
                    V4.STOX_RECEIPT_VAULT_CANDIDATE,
                    V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_CANDIDATE
                )
            )
        );
        return candidates;
    }

    /// The EU assets authoriser: a clone of the 0.1.1 authoriser whose init
    /// data names each chain's token-owner Safe, so its address is per network.
    /// @return The clone.
    function euAuthoriserClones() internal pure returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = new CloneDeploy[](1);
        clones[0] = CloneDeploy({
            suite: EU_AUTHORISER,
            factory: CLONE_FACTORY_ADDRESS,
            implementation: LibEuAuthoriserClone.implementation(),
            data: "",
            initDataPerNetwork: true,
            initData: LibEuAuthoriserClone.cloneData,
            salt: EU_AUTHORISER_SALT,
            dependencies: two(
                CLONE_FACTORY_ADDRESS,
                CLONE_FACTORY_RUNTIME_CODE,
                LibEuAuthoriserClone.implementation(),
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1
            )
        });
        return clones;
    }

    function tokenSuites() internal pure returns (RegistryBeaconProxyDeploy[] memory) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyDeploy[] memory proxies = new RegistryBeaconProxyDeploy[](configs.length);
        address beacon = vaultBeacon();
        for (uint256 i = 0; i < configs.length; i++) {
            DeployDependency[] memory deps = new DeployDependency[](3);
            deps[0] = DeployDependency({
                deployedAddress: CLONE_FACTORY_V7_ADDRESS, runtimeCode: CLONE_FACTORY_V7_RUNTIME_CODE
            });
            deps[1] =
                DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
            deps[2] = DeployDependency({deployedAddress: beacon, runtimeCode: type(UpgradeableBeacon).runtimeCode});
            proxies[i] = RegistryBeaconProxyDeploy({
                suite: string.concat("stox-token-", configs[i].underlying),
                factory: CLONE_FACTORY_V7_ADDRESS,
                registry: CONFIG_REGISTRY_ADDRESS,
                authority: LibStoxConfig.ROOT_AUTHORITY,
                beaconName: LibStoxConfig.VAULT_BEACON_NAME,
                beacon: beacon,
                data: tokenData(configs[i]),
                salt: keccak256(bytes(configs[i].underlying)),
                dependencies: deps,
                runtimeCode: LibStoxTokenProxies.runtimeCode(i)
            });
        }
        return proxies;
    }

    function tokenData(TokenConfig memory config) internal pure returns (bytes memory) {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: config.name,
                symbol: config.symbol,
                authority: LibStoxConfig.ROOT_AUTHORITY,
                rbacName: config.region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME,
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: ""
            })
        );
    }

    /// The beacon-set deployer creates the receipt beacon then the vault
    /// beacon in its constructor, so the vault beacon is its nonce-2 CREATE.
    function vaultBeacon() internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xd6),
                            bytes1(0x94),
                            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1,
                            bytes1(0x02)
                        )
                    )
                )
            )
        );
    }

    function zoltu(
        string memory suite,
        bytes memory creationCode,
        address deployedAddress,
        bytes32 bytecodeHash,
        bytes memory runtimeCode,
        string memory artifactPath,
        DeployDependency[] memory dependencies
    ) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: suite,
            creationCode: creationCode,
            storedDeployedAddress: deployedAddress,
            storedBytecodeHash: bytecodeHash,
            storedRuntimeCode: runtimeCode,
            artifactPath: artifactPath,
            dependencies: dependencies,
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            networks: new string[](0)
        });
    }

    function anchored(DeploySuite memory snapshot) internal pure returns (DeployCandidate memory) {
        return DeployCandidate({snapshot: snapshot, unanchorableReason: ""});
    }

    function one(address deployedAddress, bytes memory runtimeCode) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory deps = new DeployDependency[](1);
        deps[0] = DeployDependency({deployedAddress: deployedAddress, runtimeCode: runtimeCode});
        return deps;
    }

    function two(address a, bytes memory aRuntimeCode, address b, bytes memory bRuntimeCode)
        internal
        pure
        returns (DeployDependency[] memory)
    {
        DeployDependency[] memory deps = new DeployDependency[](2);
        deps[0] = DeployDependency({deployedAddress: a, runtimeCode: aRuntimeCode});
        deps[1] = DeployDependency({deployedAddress: b, runtimeCode: bRuntimeCode});
        return deps;
    }
}
