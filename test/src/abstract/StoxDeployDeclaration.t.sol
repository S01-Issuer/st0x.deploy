// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    ExternalDeployment,
    RainDeployDeclarationChecks,
    UndeclaredDependency,
    UnreachedDependency
} from "rain-deploy-0.1.33/src/abstract/RainDeployDeclarationChecks.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "rain-deploy-0.1.33/src/abstract/RainDeploySuitesBase.sol";
import {LibDataContract, PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    BYTECODE_HASH as CLONE_FACTORY_CODEHASH
} from "rain-factory-deploy-0.2.11/src/generated/0_1_15/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    BYTECODE_HASH as CLONE_FACTORY_V8_CODEHASH
} from "rain-factory-deploy-0.2.11/src/generated/0_2_5/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    BYTECODE_HASH as CONFIG_REGISTRY_CODEHASH
} from "rain-deploy-0.1.33/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    BYTECODE_HASH as TOFU_DECIMALS_CODEHASH
} from "rain-tofu-erc20-decimals-deploy-0.1.6/src/generated/0_1_0/TOFUTokenDecimals.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    BYTECODE_HASH as CONFIG_REGISTRY_CODEHASH
} from "rain-deploy-0.1.33/src/generated/0_1_29/ConfigRegistry.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {StoxReceiptBeacon} from "../../../src/concrete/StoxReceiptBeacon.sol";
import {StoxReceiptVaultBeacon} from "../../../src/concrete/StoxReceiptVaultBeacon.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeacon} from "../../../src/concrete/ST0xOrchestratorBeacon.sol";
import {St0xAttestSubParser} from "../../../src/concrete/St0xAttestSubParser.sol";
import {StoxGovernanceTimelock} from "../../../src/concrete/StoxGovernanceTimelock.sol";

/// @title StoxDeployDeclarationTest
/// @notice The suite fields only a dispatch, a verifier or a broadcast reads.
contract StoxDeployDeclarationTest is StoxDeploySuites, RainDeployDeclarationChecks {
    function declaration()
        internal
        view
        override(StoxDeploySuites, RainDeploySuitesBase)
        returns (DeployDeclaration memory)
    {
        DeployDeclaration memory declared = super.declaration();
        declared.sourceCreationCode = sourceCreationCode;
        declared.externalDeployments = externalDeployments();
        return declared;
    }

    function sourceCreationCode(string memory suite) internal pure returns (bytes memory) {
        bytes32 key = keccak256(bytes(suite));
        if (key == keccak256(bytes(FACET))) return type(StoxCorporateActionsFacet).creationCode;
        if (key == keccak256(bytes(RECEIPT))) return type(StoxReceipt).creationCode;
        if (key == keccak256(bytes(RECEIPT_VAULT))) return type(StoxReceiptVault).creationCode;
        if (key == keccak256(bytes(WRAPPED_TOKEN_VAULT))) return type(StoxWrappedTokenVault).creationCode;
        if (key == keccak256(bytes(WRAPPED_TOKEN_VAULT_BEACON))) return type(StoxWrappedTokenVaultBeacon).creationCode;
        if (key == keccak256(bytes(RECEIPT_BEACON))) return type(StoxReceiptBeacon).creationCode;
        if (key == keccak256(bytes(RECEIPT_VAULT_BEACON))) return type(StoxReceiptVaultBeacon).creationCode;
        if (key == keccak256(bytes(AUTHORIZER))) return type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode;
        if (key == keccak256(bytes(PAYMENT_MINT_AUTHORIZER))) {
            return type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode;
        }
        if (key == keccak256(bytes(ORCHESTRATOR))) return type(ST0xOrchestrator).creationCode;
        if (key == keccak256(bytes(ORCHESTRATOR_BEACON))) return type(ST0xOrchestratorBeacon).creationCode;
        if (key == keccak256(bytes(ATTEST_SUB_PARSER))) return type(St0xAttestSubParser).creationCode;
        if (key == keccak256(bytes(GOVERNANCE_TIMELOCK))) return type(StoxGovernanceTimelock).creationCode;
        revert(string.concat("no source for suite: ", suite));
    }

    function testDispatchChoicesAreTheSuiteKeys() external view {
        checkDispatchChoicesAreTheSuiteKeys(declaration());
    }

    function testCandidateArtifactPathsAreSource() external view {
        checkCandidateArtifactPathsAreSource(declaration());
    }

    function testDependenciesAreNonZeroAndUnique() external view {
        checkDependenciesAreNonZeroAndUnique(declaration());
    }

    function testDependenciesAreTheDeploymentsCodeEmbeds() external view {
        checkDependenciesAreTheDeploymentsCodeEmbeds(declaration());
    }

    function testDependencyRuntimeCodeIsKnown() external view {
        checkDependencyRuntimeCodeIsKnown(declaration());
    }

    function testCandidateRuntimeCodeFitsEip170() external view {
        checkCandidateRuntimeCodeFitsEip170(declaration());
    }

    function testCodeCandidateWithoutItsDependencyReverts() external {
        (DeploySuite memory timelock,) = candidateOf(declaration(), GOVERNANCE_TIMELOCK);
        assertEq(timelock.dependencies.length, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                UndeclaredDependency.selector, GOVERNANCE_TIMELOCK, timelock.dependencies[0].deployedAddress
            )
        );
        this.checkDeclarationWithoutDependenciesOf(GOVERNANCE_TIMELOCK);
    }

    function testDataContractRowsNeedNotBeDeclared() external view {
        address row = syntheticAddress("row");
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = syntheticSuite("row", hex"00");
        suites[1] = syntheticSuite("data", LibDataContract.contractCreationCode(abi.encodePacked(row)));
        this.checkSuites(suites, new ExternalDeployment[](0));
    }

    function testCodeEmbeddingUndeclaredSiblingReverts() external {
        address sibling = syntheticAddress("sibling");
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = syntheticSuite("sibling", hex"00");
        suites[1] = syntheticSuite("code", abi.encodePacked(hex"73", sibling));
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, "code", sibling));
        this.checkSuites(suites, new ExternalDeployment[](0));
    }

    function testCodeEmbeddingUndeclaredExternalReverts() external {
        address deployment = syntheticAddress("external");
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = syntheticSuite("code", abi.encodePacked(hex"73", deployment));
        ExternalDeployment[] memory externals = new ExternalDeployment[](1);
        externals[0] = ExternalDeployment({deployedAddress: deployment, codeHash: bytes32(0)});
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, "code", deployment));
        this.checkSuites(suites, externals);
    }

    function testCreationCodeOtherThanLibDataContractsIsCode() external {
        address row = syntheticAddress("row");
        bytes memory creationCode = LibDataContract.contractCreationCode(abi.encodePacked(row));
        creationCode[PREFIX_BYTES_LENGTH - 1] = 0x01;
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = syntheticSuite("row", hex"00");
        suites[1] = syntheticSuite("data", creationCode);
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, "data", row));
        this.checkSuites(suites, new ExternalDeployment[](0));
    }

    function testDataContractMechanismDataEmbeddingUndeclaredSiblingReverts() external {
        address sibling = syntheticAddress("sibling");
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = syntheticSuite("sibling", hex"00");
        suites[1] = syntheticSuite("data", LibDataContract.contractCreationCode(hex"00"));
        suites[1].mechanismData = abi.encode(sibling);
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, "data", sibling));
        this.checkSuites(suites, new ExternalDeployment[](0));
    }

    function testDataContractDeclaringUnembeddedDependencyReverts() external {
        address sibling = syntheticAddress("sibling");
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = syntheticSuite("sibling", hex"00");
        suites[1] = syntheticSuite("data", LibDataContract.contractCreationCode(hex"00"));
        suites[1].dependencies = one(sibling, hex"00");
        vm.expectRevert(abi.encodeWithSelector(UnreachedDependency.selector, "data", sibling));
        this.checkSuites(suites, new ExternalDeployment[](0));
    }

    /// A data contract's creation code only returns its data, so the addresses its rows hold need not deploy first.
    function checkDependenciesAreTheDeploymentsCodeEmbeds(DeployDeclaration memory d) internal pure {
        DeploySuite[] memory suites = allSuites(d);
        ExternalDeployment[] memory externals = d.externalDeployments;
        for (uint256 i = 0; i < suites.length; i++) {
            DeploySuite memory suite = suites[i];
            bool data = isDataContract(suite.creationCode);
            for (uint256 j = 0; j < suites.length; j++) {
                checkDeclaredIfCodeEmbeds(suite, data, suites[j].storedDeployedAddress);
            }
            for (uint256 j = 0; j < externals.length; j++) {
                checkDeclaredIfCodeEmbeds(suite, data, externals[j].deployedAddress);
            }
            DeployDependency[] memory deps = suite.dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                if (!embeds(suite, deps[j].deployedAddress)) {
                    revert UnreachedDependency(suite.suite, deps[j].deployedAddress);
                }
            }
        }
    }

    function checkDeclaredIfCodeEmbeds(DeploySuite memory suite, bool data, address deployment) internal pure {
        bool codeEmbeds = (!data && containsAddress(suite.creationCode, deployment))
            || containsAddress(suite.mechanismData, deployment);
        if (codeEmbeds && !declares(suite.dependencies, deployment)) {
            revert UndeclaredDependency(suite.suite, deployment);
        }
    }

    function isDataContract(bytes memory creationCode) internal pure returns (bool) {
        if (creationCode.length < PREFIX_BYTES_LENGTH) {
            return false;
        }
        bytes memory data = new bytes(creationCode.length - PREFIX_BYTES_LENGTH);
        for (uint256 i = 0; i < data.length; i++) {
            data[i] = creationCode[PREFIX_BYTES_LENGTH + i];
        }
        return keccak256(LibDataContract.contractCreationCode(data)) == keccak256(creationCode);
    }

    function checkDeclarationWithoutDependenciesOf(string memory suite) external view {
        DeployDeclaration memory d = declaration();
        for (uint256 i = 0; i < d.candidates.length; i++) {
            if (keccak256(bytes(d.candidates[i].snapshot.suite)) == keccak256(bytes(suite))) {
                d.candidates[i].snapshot.dependencies = new DeployDependency[](0);
            }
        }
        checkDependenciesAreTheDeploymentsCodeEmbeds(d);
    }

    function checkSuites(DeploySuite[] memory suites, ExternalDeployment[] memory externals) external pure {
        DeployDeclaration memory d;
        d.candidates = new DeployCandidate[](suites.length);
        for (uint256 i = 0; i < suites.length; i++) {
            d.candidates[i] = anchored(suites[i]);
        }
        d.externalDeployments = externals;
        checkDependenciesAreTheDeploymentsCodeEmbeds(d);
    }

    function syntheticAddress(string memory key) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(key)))));
    }

    function syntheticSuite(string memory key, bytes memory creationCode) internal pure returns (DeploySuite memory) {
        return zoltu(
            key,
            creationCode,
            syntheticAddress(key),
            bytes32(0),
            "",
            "src/Synthetic.sol:Synthetic",
            new DeployDependency[](0)
        );
    }

    function externalDeployments() internal pure returns (ExternalDeployment[] memory) {
        ExternalDeployment[] memory externals = new ExternalDeployment[](4);
        externals[0] = ExternalDeployment({deployedAddress: CLONE_FACTORY_ADDRESS, codeHash: CLONE_FACTORY_CODEHASH});
        externals[1] = ExternalDeployment({deployedAddress: TOFU_DECIMALS_ADDRESS, codeHash: TOFU_DECIMALS_CODEHASH});
        externals[2] =
            ExternalDeployment({deployedAddress: CLONE_FACTORY_V8_ADDRESS, codeHash: CLONE_FACTORY_V8_CODEHASH});
        externals[3] =
            ExternalDeployment({deployedAddress: CONFIG_REGISTRY_ADDRESS, codeHash: CONFIG_REGISTRY_CODEHASH});
        return externals;
    }
}
