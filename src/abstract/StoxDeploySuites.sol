// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "rain-deploy-0.1.30/src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "rain-deploy-0.1.30/src/lib/LibRainDeployZoltuMechanism.sol";
import {CloneDeploy} from "rain-factory-0.2.11/src/lib/LibRainDeployClone.sol";
import {LibCloneCandidates} from "rain-factory-0.2.11/src/lib/LibCloneCandidates.sol";
import {LibRainDeployCloneMechanism} from "rain-factory-0.2.11/src/lib/LibRainDeployCloneMechanism.sol";
import {
    RegistryBeaconProxyDeploy,
    RegistryBeaconProxyParams
} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_V8_RUNTIME_CODE
} from "rain-factory-deploy-0.2.8/src/generated/0_2_5/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.8/src/generated/0_1_15/CloneFactory.sol";

import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    RUNTIME_CODE as TOFU_DECIMALS_RUNTIME_CODE
} from "rain-tofu-erc20-decimals-deploy-0.1.4/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibProdDeployV4 as V4} from "../generated/LibProdDeployV4.sol";
import {EU_AUTHORISER_SALT, LibEuAuthoriserClone} from "../lib/LibEuAuthoriserClone.sol";
import {LibStoxDeployNetworks} from "../lib/LibStoxDeployNetworks.sol";
import {LibReleasedSuites} from "../lib/LibReleasedSuites.sol";
import {LibProdTokenConfig, TokenConfig} from "../lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../lib/LibProdTokenParams.sol";
import {LibStoxTokenProxy} from "../generated/LibStoxTokenProxy.sol";
import {LibStoxWrapperProxy} from "../generated/LibStoxWrapperProxy.sol";
import {LibProdOrchestratorParams} from "../lib/LibProdOrchestratorParams.sol";
import {LibST0xOrchestratorProxy} from "../generated/LibST0xOrchestratorProxy.sol";

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
    string constant RECEIPT_BEACON = "stox-receipt-beacon";
    string constant RECEIPT_VAULT_BEACON = "stox-receipt-vault-beacon";
    string constant AUTHORIZER = "stox-offchain-asset-receipt-vault-authorizer";
    string constant PAYMENT_MINT_AUTHORIZER = "stox-offchain-asset-receipt-vault-payment-mint-authorizer";
    string constant ORCHESTRATOR = LibProdOrchestratorParams.ORCHESTRATOR;
    string constant EU_AUTHORISER = "stox-eu-assets-authoriser";
    string constant UNIFIED_DEPLOYER = "stox-unified-deployer";
    string constant WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = "stox-wrapped-token-vault-beacon-set-deployer";
    string constant RECEIPT_VAULT_BEACON_SET_DEPLOYER = "stox-offchain-asset-receipt-vault-beacon-set-deployer";
    string constant ORCHESTRATOR_BEACON_SET_DEPLOYER = "stox-orchestrator-beacon-set-deployer";
    string constant ORCHESTRATOR_BEACON = "stox-orchestrator-beacon";
    string constant ORCHESTRATOR_PROXY = "stox-orchestrator-proxy";
    string constant ATTEST_SUB_PARSER = "stox-attest-sub-parser";
    string constant TOKEN_PREFIX = "stox-token-";
    string constant WRAPPER_SUFFIX = "-wrapper";
    string constant GOVERNANCE_TIMELOCK = "stox-governance-timelock";

    string constant FACET_PATH = "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet";
    string constant RECEIPT_PATH = "src/concrete/StoxReceipt.sol:StoxReceipt";
    string constant RECEIPT_VAULT_PATH = "src/concrete/StoxReceiptVault.sol:StoxReceiptVault";
    string constant WRAPPED_TOKEN_VAULT_PATH = "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault";
    string constant WRAPPED_TOKEN_VAULT_BEACON_PATH =
        "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon";
    string constant RECEIPT_BEACON_PATH = "src/concrete/StoxReceiptBeacon.sol:StoxReceiptBeacon";
    string constant RECEIPT_VAULT_BEACON_PATH = "src/concrete/StoxReceiptVaultBeacon.sol:StoxReceiptVaultBeacon";
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
    string constant ORCHESTRATOR_BEACON_PATH = "src/concrete/ST0xOrchestratorBeacon.sol:ST0xOrchestratorBeacon";
    string constant ATTEST_SUB_PARSER_PATH = "src/concrete/St0xAttestSubParser.sol:St0xAttestSubParser";
    string constant GOVERNANCE_TIMELOCK_PATH = "src/concrete/StoxGovernanceTimelock.sol:StoxGovernanceTimelock";

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
        addTokenSuites(declared, tokenConfigs());
        addTokenSuites(declared, LibProdTokenConfig.testTokenConfigs());
        LibCloneCandidates.addRegistryBeaconProxies(declared, orchestratorProxySuites());
        return declared;
    }

    function candidateSuites() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](13);
        candidates[0] = anchored(
            zoltu(
                FACET,
                V4.STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_CANDIDATE,
                V4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
                V4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_CANDIDATE,
                V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_CANDIDATE,
                FACET_PATH,
                three(
                    TOFU_DECIMALS_ADDRESS,
                    TOFU_DECIMALS_RUNTIME_CODE,
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE,
                    V4.STOX_GOVERNANCE_TIMELOCK_CANDIDATE,
                    V4.STOX_GOVERNANCE_TIMELOCK_RUNTIME_CODE_CANDIDATE
                )
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
                three(
                    V4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
                    V4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_CANDIDATE,
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE,
                    CLONE_FACTORY_V8_ADDRESS,
                    CLONE_FACTORY_V8_RUNTIME_CODE
                )
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
                two(
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE,
                    V4.STOX_WRAPPED_TOKEN_VAULT_CANDIDATE,
                    V4.STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_CANDIDATE
                )
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
                one(CONFIG_REGISTRY_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE)
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
                four(
                    V4.STOX_RECEIPT_CANDIDATE,
                    V4.STOX_RECEIPT_RUNTIME_CODE_CANDIDATE,
                    V4.STOX_RECEIPT_VAULT_CANDIDATE,
                    V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_CANDIDATE,
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE,
                    TOFU_DECIMALS_ADDRESS,
                    TOFU_DECIMALS_RUNTIME_CODE
                )
            )
        );
        candidates[8] = anchored(
            zoltu(
                ATTEST_SUB_PARSER,
                V4.ST0X_ATTEST_SUB_PARSER_CREATION_CODE_CANDIDATE,
                V4.ST0X_ATTEST_SUB_PARSER_CANDIDATE,
                V4.ST0X_ATTEST_SUB_PARSER_CODEHASH_CANDIDATE,
                V4.ST0X_ATTEST_SUB_PARSER_RUNTIME_CODE_CANDIDATE,
                ATTEST_SUB_PARSER_PATH,
                new DeployDependency[](0)
            )
        );
        candidates[9] = anchored(
            zoltu(
                GOVERNANCE_TIMELOCK,
                V4.STOX_GOVERNANCE_TIMELOCK_CREATION_CODE_CANDIDATE,
                V4.STOX_GOVERNANCE_TIMELOCK_CANDIDATE,
                V4.STOX_GOVERNANCE_TIMELOCK_CODEHASH_CANDIDATE,
                V4.STOX_GOVERNANCE_TIMELOCK_RUNTIME_CODE_CANDIDATE,
                GOVERNANCE_TIMELOCK_PATH,
                one(CONFIG_REGISTRY_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE)
            )
        );
        candidates[10] = anchored(
            zoltu(
                RECEIPT_BEACON,
                V4.STOX_RECEIPT_BEACON_CREATION_CODE_CANDIDATE,
                V4.STOX_RECEIPT_BEACON_CANDIDATE,
                V4.STOX_RECEIPT_BEACON_CODEHASH_CANDIDATE,
                V4.STOX_RECEIPT_BEACON_RUNTIME_CODE_CANDIDATE,
                RECEIPT_BEACON_PATH,
                two(
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE,
                    V4.STOX_RECEIPT_CANDIDATE,
                    V4.STOX_RECEIPT_RUNTIME_CODE_CANDIDATE
                )
            )
        );
        candidates[11] = anchored(
            zoltu(
                RECEIPT_VAULT_BEACON,
                V4.STOX_RECEIPT_VAULT_BEACON_CREATION_CODE_CANDIDATE,
                V4.STOX_RECEIPT_VAULT_BEACON_CANDIDATE,
                V4.STOX_RECEIPT_VAULT_BEACON_CODEHASH_CANDIDATE,
                V4.STOX_RECEIPT_VAULT_BEACON_RUNTIME_CODE_CANDIDATE,
                RECEIPT_VAULT_BEACON_PATH,
                two(
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE,
                    V4.STOX_RECEIPT_VAULT_CANDIDATE,
                    V4.STOX_RECEIPT_VAULT_RUNTIME_CODE_CANDIDATE
                )
            )
        );
        candidates[12] = anchored(
            zoltu(
                ORCHESTRATOR_BEACON,
                V4.ST0X_ORCHESTRATOR_BEACON_CREATION_CODE_CANDIDATE,
                V4.ST0X_ORCHESTRATOR_BEACON_CANDIDATE,
                V4.ST0X_ORCHESTRATOR_BEACON_CODEHASH_CANDIDATE,
                V4.ST0X_ORCHESTRATOR_BEACON_RUNTIME_CODE_CANDIDATE,
                ORCHESTRATOR_BEACON_PATH,
                two(
                    V4.ST0X_ORCHESTRATOR_CANDIDATE,
                    V4.ST0X_ORCHESTRATOR_RUNTIME_CODE_CANDIDATE,
                    CONFIG_REGISTRY_ADDRESS,
                    CONFIG_REGISTRY_RUNTIME_CODE
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

    /// Suite keys allow only lowercase letters and hyphens; token symbols carry uppercase.
    function lowercase(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            out[i] = c >= "A" && c <= "Z" ? bytes1(uint8(c) + 32) : c;
        }
        return string(out);
    }

    function addTokenSuites(DeployDeclaration memory declared, TokenConfig[] memory configs) internal pure {
        LibCloneCandidates.addRegistryBeaconProxies(declared, tokenSuites(configs));
        LibCloneCandidates.addRegistryBeaconProxies(declared, wrapperSuites(configs));
    }

    /// The production rows that get a token suite: those with a non-empty asset id.
    /// @return The rows.
    function tokenConfigs() internal pure returns (TokenConfig[] memory) {
        return LibProdTokenConfig.v6TokenConfigs();
    }

    /// One registry beacon proxy suite per row, keyed `TOKEN_PREFIX` + the lowercased `symbol`.
    function tokenSuites(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyDeploy[] memory) {
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        RegistryBeaconProxyDeploy[] memory suites = new RegistryBeaconProxyDeploy[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            suites[i] = RegistryBeaconProxyDeploy({
                suite: string.concat(TOKEN_PREFIX, lowercase(configs[i].symbol)),
                factory: params[i].factory,
                registry: params[i].registry,
                authority: params[i].authority,
                beaconName: params[i].beaconName,
                beacon: params[i].beacon,
                data: params[i].data,
                salt: params[i].salt,
                dependencies: LibProdTokenParams.tokenDependencies(),
                runtimeCode: LibStoxTokenProxy.RUNTIME_CODE
            });
        }
        return suites;
    }

    function wrapperSuites(TokenConfig[] memory configs) internal pure returns (RegistryBeaconProxyDeploy[] memory) {
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.wrapperParams(configs);
        RegistryBeaconProxyDeploy[] memory suites = new RegistryBeaconProxyDeploy[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            suites[i] = RegistryBeaconProxyDeploy({
                suite: string.concat(TOKEN_PREFIX, lowercase(configs[i].symbol), WRAPPER_SUFFIX),
                factory: params[i].factory,
                registry: params[i].registry,
                authority: params[i].authority,
                beaconName: params[i].beaconName,
                beacon: params[i].beacon,
                data: params[i].data,
                salt: params[i].salt,
                dependencies: LibProdTokenParams.wrapperDependencies(abi.decode(params[i].data, (address))),
                runtimeCode: LibStoxWrapperProxy.RUNTIME_CODE
            });
        }
        return suites;
    }

    function orchestratorProxySuites() internal pure returns (RegistryBeaconProxyDeploy[] memory) {
        RegistryBeaconProxyParams memory params = LibProdOrchestratorParams.orchestratorParams();
        DeployDependency[] memory dependencies = new DeployDependency[](3);
        dependencies[0] =
            DeployDependency({deployedAddress: CLONE_FACTORY_V8_ADDRESS, runtimeCode: CLONE_FACTORY_V8_RUNTIME_CODE});
        dependencies[1] =
            DeployDependency({deployedAddress: CONFIG_REGISTRY_ADDRESS, runtimeCode: CONFIG_REGISTRY_RUNTIME_CODE});
        dependencies[2] = DeployDependency({
            deployedAddress: V4.ST0X_ORCHESTRATOR_BEACON_CANDIDATE,
            runtimeCode: V4.ST0X_ORCHESTRATOR_BEACON_RUNTIME_CODE_CANDIDATE
        });
        RegistryBeaconProxyDeploy[] memory suites = new RegistryBeaconProxyDeploy[](1);
        suites[0] = RegistryBeaconProxyDeploy({
            suite: ORCHESTRATOR_PROXY,
            factory: params.factory,
            registry: params.registry,
            authority: params.authority,
            beaconName: params.beaconName,
            beacon: params.beacon,
            data: params.data,
            salt: params.salt,
            dependencies: dependencies,
            runtimeCode: LibST0xOrchestratorProxy.RUNTIME_CODE
        });
        return suites;
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
            networks: new string[](0),
            describedByMeta: ""
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

    function four(
        address a,
        bytes memory aRuntimeCode,
        address b,
        bytes memory bRuntimeCode,
        address c,
        bytes memory cRuntimeCode,
        address d,
        bytes memory dRuntimeCode
    ) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory deps = new DeployDependency[](4);
        deps[0] = DeployDependency({deployedAddress: a, runtimeCode: aRuntimeCode});
        deps[1] = DeployDependency({deployedAddress: b, runtimeCode: bRuntimeCode});
        deps[2] = DeployDependency({deployedAddress: c, runtimeCode: cRuntimeCode});
        deps[3] = DeployDependency({deployedAddress: d, runtimeCode: dRuntimeCode});
        return deps;
    }
}
