// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite,
    RainDeploySuitesBase
} from "rain-deploy-0.1.22/src/abstract/RainDeploySuitesBase.sol";
import {CloneDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeployClone.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "rain-deploy-0.1.22/src/lib/LibRainDeployMechanism.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.2/src/generated/0_1_15/CloneFactory.sol";

import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    RUNTIME_CODE as TOFU_DECIMALS_RUNTIME_CODE
} from "rain-tofu-erc20-decimals-deploy-0.1.3/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {EU_AUTHORISER_SALT, LibEuAuthoriserClone} from "../lib/LibEuAuthoriserClone.sol";
import {LibStoxDeployNetworks} from "../lib/LibStoxDeployNetworks.sol";

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
    function supportedNetworks() internal view virtual override returns (string[] memory) {
        return LibStoxDeployNetworks.deploymentNetworks();
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](16);
        suites[0] = zoltu(
            string.concat(FACET, "@0_1_1"),
            V4.STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_0_1_1,
            V4.STOX_CORPORATE_ACTIONS_FACET_0_1_1,
            V4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_1,
            V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_1,
            FACET_PATH,
            one(TOFU_DECIMALS_ADDRESS, TOFU_DECIMALS_RUNTIME_CODE)
        );
        suites[1] = zoltu(
            string.concat(RECEIPT, "@0_1_1"),
            V4.STOX_RECEIPT_CREATION_CODE_0_1_1,
            V4.STOX_RECEIPT_0_1_1,
            V4.STOX_RECEIPT_CODEHASH_0_1_1,
            V4.STOX_RECEIPT_RUNTIME_CODE_0_1_1,
            RECEIPT_PATH,
            new DeployDependency[](0)
        );
        suites[2] = zoltu(
            string.concat(RECEIPT_VAULT, "@0_1_1"),
            V4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1,
            V4.STOX_RECEIPT_VAULT_0_1_1,
            V4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1,
            V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_1,
            RECEIPT_VAULT_PATH,
            one(V4.STOX_CORPORATE_ACTIONS_FACET_0_1_1, V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_1)
        );
        suites[3] = zoltu(
            string.concat(WRAPPED_TOKEN_VAULT, "@0_1_1"),
            V4.STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_0_1_1,
            WRAPPED_TOKEN_VAULT_PATH,
            new DeployDependency[](0)
        );
        suites[4] = zoltu(
            string.concat(WRAPPED_TOKEN_VAULT_BEACON, "@0_1_1"),
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_0_1_1,
            WRAPPED_TOKEN_VAULT_BEACON_PATH,
            one(V4.STOX_WRAPPED_TOKEN_VAULT_0_1_1, V4.STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_0_1_1)
        );
        suites[5] = zoltu(
            string.concat(WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER, "@0_1_1"),
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1,
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1,
            WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_PATH,
            one(V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1, V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_0_1_1)
        );
        suites[6] = zoltu(
            string.concat(RECEIPT_VAULT_BEACON_SET_DEPLOYER, "@0_1_1"),
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1,
            RECEIPT_VAULT_BEACON_SET_DEPLOYER_PATH,
            two(
                V4.STOX_RECEIPT_0_1_1,
                V4.STOX_RECEIPT_RUNTIME_CODE_0_1_1,
                V4.STOX_RECEIPT_VAULT_0_1_1,
                V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_1
            )
        );
        suites[7] = zoltu(
            string.concat(UNIFIED_DEPLOYER, "@0_1_1"),
            V4.STOX_UNIFIED_DEPLOYER_CREATION_CODE_0_1_1,
            V4.STOX_UNIFIED_DEPLOYER_0_1_1,
            V4.STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_1,
            V4.STOX_UNIFIED_DEPLOYER_RUNTIME_CODE_0_1_1,
            UNIFIED_DEPLOYER_PATH,
            two(
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1,
                V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1,
                V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1
            )
        );
        suites[8] = zoltu(
            string.concat(AUTHORIZER, "@0_1_1"),
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_CODE_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1,
            AUTHORIZER_PATH,
            new DeployDependency[](0)
        );
        suites[9] = zoltu(
            string.concat(PAYMENT_MINT_AUTHORIZER, "@0_1_1"),
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_CODE_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_0_1_1,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1,
            PAYMENT_MINT_AUTHORIZER_PATH,
            new DeployDependency[](0)
        );
        suites[10] = zoltu(
            string.concat(FACET, "@0_1_30"),
            V4.STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_0_1_30,
            V4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            V4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_30,
            V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_30,
            FACET_PATH,
            one(TOFU_DECIMALS_ADDRESS, TOFU_DECIMALS_RUNTIME_CODE)
        );
        suites[11] = zoltu(
            string.concat(RECEIPT, "@0_1_30"),
            V4.STOX_RECEIPT_CREATION_CODE_0_1_30,
            V4.STOX_RECEIPT_0_1_30,
            V4.STOX_RECEIPT_CODEHASH_0_1_30,
            V4.STOX_RECEIPT_RUNTIME_CODE_0_1_30,
            RECEIPT_PATH,
            new DeployDependency[](0)
        );
        suites[12] = zoltu(
            string.concat(RECEIPT_VAULT, "@0_1_30"),
            V4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_30,
            V4.STOX_RECEIPT_VAULT_0_1_30,
            V4.STOX_RECEIPT_VAULT_CODEHASH_0_1_30,
            V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_30,
            RECEIPT_VAULT_PATH,
            one(V4.STOX_CORPORATE_ACTIONS_FACET_0_1_30, V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_30)
        );
        suites[13] = zoltu(
            string.concat(RECEIPT_VAULT_BEACON_SET_DEPLOYER, "@0_1_30"),
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_30,
            V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_30,
            RECEIPT_VAULT_BEACON_SET_DEPLOYER_PATH,
            two(
                V4.STOX_RECEIPT_0_1_30,
                V4.STOX_RECEIPT_RUNTIME_CODE_0_1_30,
                V4.STOX_RECEIPT_VAULT_0_1_30,
                V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_30
            )
        );
        suites[14] = zoltu(
            string.concat(ORCHESTRATOR, "@0_1_30"),
            V4.ST0X_ORCHESTRATOR_CREATION_CODE_0_1_30,
            V4.ST0X_ORCHESTRATOR_0_1_30,
            V4.ST0X_ORCHESTRATOR_CODEHASH_0_1_30,
            V4.ST0X_ORCHESTRATOR_RUNTIME_CODE_0_1_30,
            ORCHESTRATOR_PATH,
            three(
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30,
                V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_30,
                V4.STOX_RECEIPT_0_1_30,
                V4.STOX_RECEIPT_RUNTIME_CODE_0_1_30,
                V4.STOX_RECEIPT_VAULT_0_1_30,
                V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_30
            )
        );
        suites[15] = zoltu(
            string.concat(ORCHESTRATOR_BEACON_SET_DEPLOYER, "@0_1_30"),
            V4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30,
            V4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            V4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_0_1_30,
            V4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_30,
            ORCHESTRATOR_BEACON_SET_DEPLOYER_PATH,
            one(V4.ST0X_ORCHESTRATOR_0_1_30, V4.ST0X_ORCHESTRATOR_RUNTIME_CODE_0_1_30)
        );
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](9);
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
        candidates[8] = euAuthoriserCandidate();
        return candidates;
    }

    /// The EU assets authoriser: a clone of the 0.1.1 authoriser whose init
    /// data names each chain's token-owner Safe, so its address is per network.
    /// @return The candidate.
    function euAuthoriserCandidate() internal view returns (DeployCandidate memory) {
        return LibRainDeployMechanism.cloneCandidate(
            CloneDeploy({
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
            }),
            supportedChainIds()
        );
    }

    /// @return The chain id of every network in `supportedNetworks()`, in order.
    function supportedChainIds() internal view returns (uint256[] memory) {
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(supportedNetworks());
        uint256[] memory chainIds = new uint256[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            chainIds[i] = configs[i].chainId;
        }
        return chainIds;
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
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
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

    function three(
        address a,
        bytes memory aRuntimeCode,
        address b,
        bytes memory bRuntimeCode,
        address c,
        bytes memory cRuntimeCode
    ) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory deps = new DeployDependency[](3);
        deps[0] = DeployDependency({deployedAddress: a, runtimeCode: aRuntimeCode});
        deps[1] = DeployDependency({deployedAddress: b, runtimeCode: bRuntimeCode});
        deps[2] = DeployDependency({deployedAddress: c, runtimeCode: cRuntimeCode});
        return deps;
    }
}
