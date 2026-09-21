// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
import {
    DEPLOYED_ADDRESS as StoxCorporateActionsFacet_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxCorporateActionsFacet_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxCorporateActionsFacet_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxCorporateActionsFacet_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxCorporateActionsFacet.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxReceipt_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxReceipt_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxReceipt_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxReceipt_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxReceipt.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxReceiptVault_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxReceiptVault_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxReceiptVault_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxReceiptVault_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxReceiptVault.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxWrappedTokenVault_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxWrappedTokenVault_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxWrappedTokenVault_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxWrappedTokenVault_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxWrappedTokenVault.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxWrappedTokenVaultBeacon_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxWrappedTokenVaultBeacon_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxWrappedTokenVaultBeacon_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxWrappedTokenVaultBeacon_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxUnifiedDeployer_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxUnifiedDeployer_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxUnifiedDeployer_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxUnifiedDeployer_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxUnifiedDeployer.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_BYTECODE_HASH,
    CREATION_CODE as StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_CREATION_CODE,
    RUNTIME_CODE as StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_RUNTIME_CODE
} from "../generated/0_1_1/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxCorporateActionsFacet_0_1_30_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxCorporateActionsFacet_0_1_30_BYTECODE_HASH,
    CREATION_CODE as StoxCorporateActionsFacet_0_1_30_CREATION_CODE,
    RUNTIME_CODE as StoxCorporateActionsFacet_0_1_30_RUNTIME_CODE
} from "../generated/0_1_30/StoxCorporateActionsFacet.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxReceipt_0_1_30_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxReceipt_0_1_30_BYTECODE_HASH,
    CREATION_CODE as StoxReceipt_0_1_30_CREATION_CODE,
    RUNTIME_CODE as StoxReceipt_0_1_30_RUNTIME_CODE
} from "../generated/0_1_30/StoxReceipt.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxReceiptVault_0_1_30_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxReceiptVault_0_1_30_BYTECODE_HASH,
    CREATION_CODE as StoxReceiptVault_0_1_30_CREATION_CODE,
    RUNTIME_CODE as StoxReceiptVault_0_1_30_RUNTIME_CODE
} from "../generated/0_1_30/StoxReceiptVault.pointers.sol";
import {
    DEPLOYED_ADDRESS as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_DEPLOYED_ADDRESS,
    BYTECODE_HASH as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_BYTECODE_HASH,
    CREATION_CODE as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_CREATION_CODE,
    RUNTIME_CODE as StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_RUNTIME_CODE
} from "../generated/0_1_30/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";
import {
    DEPLOYED_ADDRESS as ST0xOrchestrator_0_1_30_DEPLOYED_ADDRESS,
    BYTECODE_HASH as ST0xOrchestrator_0_1_30_BYTECODE_HASH,
    CREATION_CODE as ST0xOrchestrator_0_1_30_CREATION_CODE,
    RUNTIME_CODE as ST0xOrchestrator_0_1_30_RUNTIME_CODE
} from "../generated/0_1_30/ST0xOrchestrator.pointers.sol";
import {
    DEPLOYED_ADDRESS as ST0xOrchestratorBeaconSetDeployer_0_1_30_DEPLOYED_ADDRESS,
    BYTECODE_HASH as ST0xOrchestratorBeaconSetDeployer_0_1_30_BYTECODE_HASH,
    CREATION_CODE as ST0xOrchestratorBeaconSetDeployer_0_1_30_CREATION_CODE,
    RUNTIME_CODE as ST0xOrchestratorBeaconSetDeployer_0_1_30_RUNTIME_CODE
} from "../generated/0_1_30/ST0xOrchestratorBeaconSetDeployer.pointers.sol";

/// @title LibStoxLegacyReleased
/// @notice The releases frozen before this repo built on `rain-deploy`'s
/// record format: `0_1_1` and `0_1_30`.
///
/// `LibRainDeploySnapshot` emits a released entry from a record file named
/// `<Contract>.sol` that carries a frozen `DEPENDENCIES` constant. These two
/// releases were frozen as `<Contract>.pointers.sol` with no dependency list,
/// so the generated `LibReleasedSuites` cannot name them, and the record is
/// append-only, so they are not rewritten into that shape either. They are
/// declared here instead, aliasing each frozen file directly, so what each
/// entry deploys and pins is still read from the immutable record and from
/// nowhere else.
///
/// The dependency lists are the ones these releases were broadcast with by the
/// per-release deploy scripts this declaration replaced.
///
/// `RainDeployVerifySnapshotBase.checkFrozenSnapshotsReleased` matches record
/// files to released suites by address, not by file name, so it holds these
/// files to this declaration exactly as it holds a generated record to the
/// generated one.
library LibStoxLegacyReleased {
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

    /// Every legacy frozen release, in tag order.
    /// @return The released suites.
    function releasedSuites() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](16);
        suites[0] = DeploySuite({
            suite: "stox-corporate-actions-facet@0_1_1",
            creationCode: StoxCorporateActionsFacet_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxCorporateActionsFacet_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxCorporateActionsFacet_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxCorporateActionsFacet_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            dependencies: noDependencies()
        });
        suites[1] = DeploySuite({
            suite: "stox-receipt@0_1_1",
            creationCode: StoxReceipt_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxReceipt_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxReceipt_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxReceipt_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxReceipt.sol:StoxReceipt",
            dependencies: noDependencies()
        });
        suites[2] = DeploySuite({
            suite: "stox-receipt-vault@0_1_1",
            creationCode: StoxReceiptVault_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxReceiptVault_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxReceiptVault_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxReceiptVault_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
            dependencies: dependencies(StoxCorporateActionsFacet_0_1_1_DEPLOYED_ADDRESS)
        });
        suites[3] = DeploySuite({
            suite: "stox-wrapped-token-vault@0_1_1",
            creationCode: StoxWrappedTokenVault_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxWrappedTokenVault_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxWrappedTokenVault_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxWrappedTokenVault_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            dependencies: noDependencies()
        });
        suites[4] = DeploySuite({
            suite: "stox-wrapped-token-vault-beacon@0_1_1",
            creationCode: StoxWrappedTokenVaultBeacon_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxWrappedTokenVaultBeacon_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxWrappedTokenVaultBeacon_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxWrappedTokenVaultBeacon_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxWrappedTokenVaultBeacon.sol:StoxWrappedTokenVaultBeacon",
            dependencies: dependencies(StoxWrappedTokenVault_0_1_1_DEPLOYED_ADDRESS)
        });
        suites[5] = DeploySuite({
            suite: "stox-wrapped-token-vault-beacon-set-deployer@0_1_1",
            creationCode: StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol:StoxWrappedTokenVaultBeaconSetDeployer",
            dependencies: dependencies(StoxWrappedTokenVaultBeacon_0_1_1_DEPLOYED_ADDRESS)
        });
        suites[6] = DeploySuite({
            suite: "stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_1",
            creationCode: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            dependencies: dependencies(StoxReceipt_0_1_1_DEPLOYED_ADDRESS, StoxReceiptVault_0_1_1_DEPLOYED_ADDRESS)
        });
        suites[7] = DeploySuite({
            suite: "stox-unified-deployer@0_1_1",
            creationCode: StoxUnifiedDeployer_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxUnifiedDeployer_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxUnifiedDeployer_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxUnifiedDeployer_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/deploy/StoxUnifiedDeployer.sol:StoxUnifiedDeployer",
            dependencies: dependencies(
                StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_1_DEPLOYED_ADDRESS,
                StoxWrappedTokenVaultBeaconSetDeployer_0_1_1_DEPLOYED_ADDRESS
            )
        });
        suites[8] = DeploySuite({
            suite: "stox-offchain-asset-receipt-vault-authorizer@0_1_1",
            creationCode: StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxOffchainAssetReceiptVaultAuthorizerV1_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol:StoxOffchainAssetReceiptVaultAuthorizerV1",
            dependencies: noDependencies()
        });
        suites[9] = DeploySuite({
            suite: "stox-offchain-asset-receipt-vault-payment-mint-authorizer@0_1_1",
            creationCode: StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_CREATION_CODE,
            storedDeployedAddress: StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_BYTECODE_HASH,
            storedRuntimeCode: StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1_0_1_1_RUNTIME_CODE,
            artifactPath: "src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol:StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
            dependencies: noDependencies()
        });
        suites[10] = DeploySuite({
            suite: "stox-corporate-actions-facet@0_1_30",
            creationCode: StoxCorporateActionsFacet_0_1_30_CREATION_CODE,
            storedDeployedAddress: StoxCorporateActionsFacet_0_1_30_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxCorporateActionsFacet_0_1_30_BYTECODE_HASH,
            storedRuntimeCode: StoxCorporateActionsFacet_0_1_30_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            dependencies: noDependencies()
        });
        suites[11] = DeploySuite({
            suite: "stox-receipt@0_1_30",
            creationCode: StoxReceipt_0_1_30_CREATION_CODE,
            storedDeployedAddress: StoxReceipt_0_1_30_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxReceipt_0_1_30_BYTECODE_HASH,
            storedRuntimeCode: StoxReceipt_0_1_30_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxReceipt.sol:StoxReceipt",
            dependencies: noDependencies()
        });
        suites[12] = DeploySuite({
            suite: "stox-receipt-vault@0_1_30",
            creationCode: StoxReceiptVault_0_1_30_CREATION_CODE,
            storedDeployedAddress: StoxReceiptVault_0_1_30_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxReceiptVault_0_1_30_BYTECODE_HASH,
            storedRuntimeCode: StoxReceiptVault_0_1_30_RUNTIME_CODE,
            artifactPath: "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
            dependencies: dependencies(StoxCorporateActionsFacet_0_1_30_DEPLOYED_ADDRESS)
        });
        suites[13] = DeploySuite({
            suite: "stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_30",
            creationCode: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_CREATION_CODE,
            storedDeployedAddress: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_DEPLOYED_ADDRESS,
            storedBytecodeHash: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_BYTECODE_HASH,
            storedRuntimeCode: StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_RUNTIME_CODE,
            artifactPath: "src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol:StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            dependencies: dependencies(StoxReceipt_0_1_30_DEPLOYED_ADDRESS, StoxReceiptVault_0_1_30_DEPLOYED_ADDRESS)
        });
        suites[14] = DeploySuite({
            suite: "stox-orchestrator@0_1_30",
            creationCode: ST0xOrchestrator_0_1_30_CREATION_CODE,
            storedDeployedAddress: ST0xOrchestrator_0_1_30_DEPLOYED_ADDRESS,
            storedBytecodeHash: ST0xOrchestrator_0_1_30_BYTECODE_HASH,
            storedRuntimeCode: ST0xOrchestrator_0_1_30_RUNTIME_CODE,
            artifactPath: "src/concrete/ST0xOrchestrator.sol:ST0xOrchestrator",
            dependencies: dependencies(StoxOffchainAssetReceiptVaultBeaconSetDeployer_0_1_30_DEPLOYED_ADDRESS)
        });
        suites[15] = DeploySuite({
            suite: "stox-orchestrator-beacon-set-deployer@0_1_30",
            creationCode: ST0xOrchestratorBeaconSetDeployer_0_1_30_CREATION_CODE,
            storedDeployedAddress: ST0xOrchestratorBeaconSetDeployer_0_1_30_DEPLOYED_ADDRESS,
            storedBytecodeHash: ST0xOrchestratorBeaconSetDeployer_0_1_30_BYTECODE_HASH,
            storedRuntimeCode: ST0xOrchestratorBeaconSetDeployer_0_1_30_RUNTIME_CODE,
            artifactPath: "src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol:ST0xOrchestratorBeaconSetDeployer",
            dependencies: dependencies(ST0xOrchestrator_0_1_30_DEPLOYED_ADDRESS)
        });
        return suites;
    }
}
