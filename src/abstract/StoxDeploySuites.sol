// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {LibReleasedSuites} from "../lib/LibReleasedSuites.sol";
import {LibStoxLegacyReleased} from "../lib/LibStoxLegacyReleased.sol";
import {StoxCorporateActionsFacet} from "../concrete/StoxCorporateActionsFacet.sol";
import {StoxReceipt} from "../concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../concrete/StoxWrappedTokenVaultBeacon.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "../concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {StoxUnifiedDeployer} from "../concrete/deploy/StoxUnifiedDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {ST0xOrchestrator} from "../concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {
    DEPLOYED_ADDRESS as FACET_ADDRESS,
    BYTECODE_HASH as FACET_HASH,
    CREATION_CODE as FACET_CREATION_CODE,
    RUNTIME_CODE as FACET_RUNTIME_CODE
} from "../generated/candidate/StoxCorporateActionsFacet.sol";
import {
    DEPLOYED_ADDRESS as RECEIPT_ADDRESS,
    BYTECODE_HASH as RECEIPT_HASH,
    CREATION_CODE as RECEIPT_CREATION_CODE,
    RUNTIME_CODE as RECEIPT_RUNTIME_CODE
} from "../generated/candidate/StoxReceipt.sol";
import {
    DEPLOYED_ADDRESS as RECEIPT_VAULT_ADDRESS,
    BYTECODE_HASH as RECEIPT_VAULT_HASH,
    CREATION_CODE as RECEIPT_VAULT_CREATION_CODE,
    RUNTIME_CODE as RECEIPT_VAULT_RUNTIME_CODE
} from "../generated/candidate/StoxReceiptVault.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_VAULT_ADDRESS,
    BYTECODE_HASH as WRAPPED_VAULT_HASH,
    CREATION_CODE as WRAPPED_VAULT_CREATION_CODE,
    RUNTIME_CODE as WRAPPED_VAULT_RUNTIME_CODE
} from "../generated/candidate/StoxWrappedTokenVault.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_BEACON_ADDRESS,
    BYTECODE_HASH as WRAPPED_BEACON_HASH,
    CREATION_CODE as WRAPPED_BEACON_CREATION_CODE,
    RUNTIME_CODE as WRAPPED_BEACON_RUNTIME_CODE
} from "../generated/candidate/StoxWrappedTokenVaultBeacon.sol";
import {
    DEPLOYED_ADDRESS as WRAPPED_SET_DEPLOYER_ADDRESS,
    BYTECODE_HASH as WRAPPED_SET_DEPLOYER_HASH,
    CREATION_CODE as WRAPPED_SET_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as WRAPPED_SET_DEPLOYER_RUNTIME_CODE
} from "../generated/candidate/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    DEPLOYED_ADDRESS as OARV_SET_DEPLOYER_ADDRESS,
    BYTECODE_HASH as OARV_SET_DEPLOYER_HASH,
    CREATION_CODE as OARV_SET_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as OARV_SET_DEPLOYER_RUNTIME_CODE
} from "../generated/candidate/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    DEPLOYED_ADDRESS as UNIFIED_DEPLOYER_ADDRESS,
    BYTECODE_HASH as UNIFIED_DEPLOYER_HASH,
    CREATION_CODE as UNIFIED_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as UNIFIED_DEPLOYER_RUNTIME_CODE
} from "../generated/candidate/StoxUnifiedDeployer.sol";
import {
    DEPLOYED_ADDRESS as AUTHORIZER_ADDRESS,
    BYTECODE_HASH as AUTHORIZER_HASH,
    CREATION_CODE as AUTHORIZER_CREATION_CODE,
    RUNTIME_CODE as AUTHORIZER_RUNTIME_CODE
} from "../generated/candidate/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    DEPLOYED_ADDRESS as PAYMENT_MINT_AUTHORIZER_ADDRESS,
    BYTECODE_HASH as PAYMENT_MINT_AUTHORIZER_HASH,
    CREATION_CODE as PAYMENT_MINT_AUTHORIZER_CREATION_CODE,
    RUNTIME_CODE as PAYMENT_MINT_AUTHORIZER_RUNTIME_CODE
} from "../generated/candidate/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {
    DEPLOYED_ADDRESS as ORCHESTRATOR_ADDRESS,
    BYTECODE_HASH as ORCHESTRATOR_HASH,
    CREATION_CODE as ORCHESTRATOR_CREATION_CODE,
    RUNTIME_CODE as ORCHESTRATOR_RUNTIME_CODE
} from "../generated/candidate/ST0xOrchestrator.sol";
import {
    DEPLOYED_ADDRESS as ORCHESTRATOR_SET_DEPLOYER_ADDRESS,
    BYTECODE_HASH as ORCHESTRATOR_SET_DEPLOYER_HASH,
    CREATION_CODE as ORCHESTRATOR_SET_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as ORCHESTRATOR_SET_DEPLOYER_RUNTIME_CODE
} from "../generated/candidate/ST0xOrchestratorBeaconSetDeployer.sol";

/// @title StoxDeploySuites
/// @notice Everything this repo deploys, declared once and inherited by
/// `script/Build.sol` and `script/Deploy.sol`.
///
/// The candidates are the twelve contracts current source compiles, in the
/// order they have to reach a chain: each one's dependencies are declared
/// before it. The released side is the legacy `0_1_1` / `0_1_30` record
/// (`LibStoxLegacyReleased`) followed by every release cut since, which
/// `script/Build.sol` generates into `LibReleasedSuites` from the record.
///
/// The suite keys are the `Manual sol artifacts` dispatch choices and MUST stay
/// in step with `.github/workflows/manual-sol-artifacts.yaml`.
abstract contract StoxDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory legacy = LibStoxLegacyReleased.releasedSuites();
        DeploySuite[] memory generated = LibReleasedSuites.releasedSuites();
        DeploySuite[] memory suites = new DeploySuite[](legacy.length + generated.length);
        for (uint256 i = 0; i < legacy.length; i++) {
            suites[i] = legacy[i];
        }
        for (uint256 i = 0; i < generated.length; i++) {
            suites[legacy.length + i] = generated[i];
        }
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](12);
        candidates[0] = facetCandidate();
        candidates[1] = receiptCandidate();
        candidates[2] = receiptVaultCandidate();
        candidates[3] = wrappedVaultCandidate();
        candidates[4] = wrappedBeaconCandidate();
        candidates[5] = wrappedSetDeployerCandidate();
        candidates[6] = oarvSetDeployerCandidate();
        candidates[7] = unifiedDeployerCandidate();
        candidates[8] = authorizerCandidate();
        candidates[9] = paymentMintAuthorizerCandidate();
        candidates[10] = orchestratorCandidate();
        candidates[11] = orchestratorSetDeployerCandidate();
        return candidates;
    }

    /// No dependencies.
    /// @return The dependency addresses: none.
    function noDependencies() internal pure returns (address[] memory) {
        return new address[](0);
    }

    /// One dependency.
    /// @param a The dependency.
    /// @return The dependency addresses.
    function dependencies(address a) internal pure returns (address[] memory) {
        address[] memory deps = new address[](1);
        deps[0] = a;
        return deps;
    }

    /// Two dependencies, in the order given.
    /// @param a The first dependency.
    /// @param b The second dependency.
    /// @return The dependency addresses.
    function dependencies(address a, address b) internal pure returns (address[] memory) {
        address[] memory deps = new address[](2);
        deps[0] = a;
        deps[1] = b;
        return deps;
    }

    /// The corporate-actions facet. No dependencies: the receipt vault
    /// hardcodes its address, not the other way round.
    /// @return The candidate.
    function facetCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-corporate-actions-facet",
                creationCode: FACET_CREATION_CODE,
                storedDeployedAddress: FACET_ADDRESS,
                storedBytecodeHash: FACET_HASH,
                storedRuntimeCode: FACET_RUNTIME_CODE,
                artifactPath: "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
                dependencies: noDependencies()
            }),
            sourceCreationCode: type(StoxCorporateActionsFacet).creationCode
        });
    }

    /// The receipt implementation. No dependencies.
    /// @return The candidate.
    function receiptCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-receipt",
                creationCode: RECEIPT_CREATION_CODE,
                storedDeployedAddress: RECEIPT_ADDRESS,
                storedBytecodeHash: RECEIPT_HASH,
                storedRuntimeCode: RECEIPT_RUNTIME_CODE,
                artifactPath: "src/concrete/StoxReceipt.sol:StoxReceipt",
                dependencies: noDependencies()
            }),
            sourceCreationCode: type(StoxReceipt).creationCode
        });
    }

    /// The receipt vault implementation. Depends on the facet: its `fallback()`
    /// delegatecalls it, and a delegatecall to a code-less address silently
    /// no-ops.
    /// @return The candidate.
    function receiptVaultCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-receipt-vault",
                creationCode: RECEIPT_VAULT_CREATION_CODE,
                storedDeployedAddress: RECEIPT_VAULT_ADDRESS,
                storedBytecodeHash: RECEIPT_VAULT_HASH,
                storedRuntimeCode: RECEIPT_VAULT_RUNTIME_CODE,
                artifactPath: "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
                dependencies: dependencies(FACET_ADDRESS)
            }),
            sourceCreationCode: type(StoxReceiptVault).creationCode
        });
    }

    /// The wrapped token vault implementation. No dependencies.
    /// @return The candidate.
    function wrappedVaultCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-wrapped-token-vault",
                creationCode: WRAPPED_VAULT_CREATION_CODE,
                storedDeployedAddress: WRAPPED_VAULT_ADDRESS,
                storedBytecodeHash: WRAPPED_VAULT_HASH,
                storedRuntimeCode: WRAPPED_VAULT_RUNTIME_CODE,
                artifactPath: "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
                dependencies: noDependencies()
            }),
            sourceCreationCode: type(StoxWrappedTokenVault).creationCode
        });
    }

    /// The wrapped token vault beacon. Depends on the implementation it points
    /// at.
    /// @return The candidate.
    function wrappedBeaconCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-wrapped-token-vault-beacon",
                creationCode: WRAPPED_BEACON_CREATION_CODE,
                storedDeployedAddress: WRAPPED_BEACON_ADDRESS,
                storedBytecodeHash: WRAPPED_BEACON_HASH,
                storedRuntimeCode: WRAPPED_BEACON_RUNTIME_CODE,
                artifactPath: "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon",
                dependencies: dependencies(WRAPPED_VAULT_ADDRESS)
            }),
            sourceCreationCode: type(StoxWrappedTokenVaultBeacon).creationCode
        });
    }

    /// The wrapped token vault beacon-set deployer. Depends on the beacon it
    /// deploys proxies of.
    /// @return The candidate.
    function wrappedSetDeployerCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-wrapped-token-vault-beacon-set-deployer",
                creationCode: WRAPPED_SET_DEPLOYER_CREATION_CODE,
                storedDeployedAddress: WRAPPED_SET_DEPLOYER_ADDRESS,
                storedBytecodeHash: WRAPPED_SET_DEPLOYER_HASH,
                storedRuntimeCode: WRAPPED_SET_DEPLOYER_RUNTIME_CODE,
                artifactPath: "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer",
                dependencies: dependencies(WRAPPED_BEACON_ADDRESS)
            }),
            sourceCreationCode: type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode
        });
    }

    /// The offchain asset receipt vault beacon-set deployer. Its constructor
    /// bakes beacons over the receipt and receipt vault implementations, both
    /// of which must already have code.
    /// @return The candidate.
    function oarvSetDeployerCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-offchain-asset-receipt-vault-beacon-set-deployer",
                creationCode: OARV_SET_DEPLOYER_CREATION_CODE,
                storedDeployedAddress: OARV_SET_DEPLOYER_ADDRESS,
                storedBytecodeHash: OARV_SET_DEPLOYER_HASH,
                storedRuntimeCode: OARV_SET_DEPLOYER_RUNTIME_CODE,
                artifactPath: "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
                dependencies: dependencies(RECEIPT_ADDRESS, RECEIPT_VAULT_ADDRESS)
            }),
            sourceCreationCode: type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode
        });
    }

    /// The unified deployer. Depends on both beacon-set deployers it drives.
    /// @return The candidate.
    function unifiedDeployerCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-unified-deployer",
                creationCode: UNIFIED_DEPLOYER_CREATION_CODE,
                storedDeployedAddress: UNIFIED_DEPLOYER_ADDRESS,
                storedBytecodeHash: UNIFIED_DEPLOYER_HASH,
                storedRuntimeCode: UNIFIED_DEPLOYER_RUNTIME_CODE,
                artifactPath: "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
                dependencies: dependencies(OARV_SET_DEPLOYER_ADDRESS, WRAPPED_SET_DEPLOYER_ADDRESS)
            }),
            sourceCreationCode: type(StoxUnifiedDeployer).creationCode
        });
    }

    /// The receipt vault authorizer implementation. No dependencies.
    /// @return The candidate.
    function authorizerCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-offchain-asset-receipt-vault-authorizer",
                creationCode: AUTHORIZER_CREATION_CODE,
                storedDeployedAddress: AUTHORIZER_ADDRESS,
                storedBytecodeHash: AUTHORIZER_HASH,
                storedRuntimeCode: AUTHORIZER_RUNTIME_CODE,
                artifactPath: "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol:StoxOffchainAssetReceiptVaultAuthorizerV1",
                dependencies: noDependencies()
            }),
            sourceCreationCode: type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode
        });
    }

    /// The payment-mint authorizer implementation. No dependencies.
    /// @return The candidate.
    function paymentMintAuthorizerCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-offchain-asset-receipt-vault-payment-mint-authorizer",
                creationCode: PAYMENT_MINT_AUTHORIZER_CREATION_CODE,
                storedDeployedAddress: PAYMENT_MINT_AUTHORIZER_ADDRESS,
                storedBytecodeHash: PAYMENT_MINT_AUTHORIZER_HASH,
                storedRuntimeCode: PAYMENT_MINT_AUTHORIZER_RUNTIME_CODE,
                artifactPath: "src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol:StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
                dependencies: noDependencies()
            }),
            sourceCreationCode: type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode
        });
    }

    /// The orchestrator implementation. `initialize` (and mint/burn) revert via
    /// the vault-logic version lock unless the offchain asset receipt vault
    /// beacon-set deployer it was built against has code.
    /// @return The candidate.
    function orchestratorCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-orchestrator",
                creationCode: ORCHESTRATOR_CREATION_CODE,
                storedDeployedAddress: ORCHESTRATOR_ADDRESS,
                storedBytecodeHash: ORCHESTRATOR_HASH,
                storedRuntimeCode: ORCHESTRATOR_RUNTIME_CODE,
                artifactPath: "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator",
                dependencies: dependencies(OARV_SET_DEPLOYER_ADDRESS)
            }),
            sourceCreationCode: type(ST0xOrchestrator).creationCode
        });
    }

    /// The orchestrator beacon-set deployer. Its constructor bakes a beacon
    /// over the orchestrator implementation, which must already have code.
    /// @return The candidate.
    function orchestratorSetDeployerCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "stox-orchestrator-beacon-set-deployer",
                creationCode: ORCHESTRATOR_SET_DEPLOYER_CREATION_CODE,
                storedDeployedAddress: ORCHESTRATOR_SET_DEPLOYER_ADDRESS,
                storedBytecodeHash: ORCHESTRATOR_SET_DEPLOYER_HASH,
                storedRuntimeCode: ORCHESTRATOR_SET_DEPLOYER_RUNTIME_CODE,
                artifactPath: "src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol:ST0xOrchestratorBeaconSetDeployer",
                dependencies: dependencies(ORCHESTRATOR_ADDRESS)
            }),
            sourceCreationCode: type(ST0xOrchestratorBeaconSetDeployer).creationCode
        });
    }
}
