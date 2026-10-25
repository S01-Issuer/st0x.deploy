// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite
} from "rain-deploy-0.1.22/src/abstract/RainDeploySuitesBase.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    BYTECODE_HASH as CLONE_FACTORY_CODEHASH
} from "rain-factory-deploy-0.2.2/src/generated/0_1_15/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    BYTECODE_HASH as TOFU_DECIMALS_CODEHASH
} from "rain-tofu-erc20-decimals-deploy-0.1.3/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibTOFUTokenDecimals} from "rain-tofu-erc20-decimals-0.1.4/src/lib/LibTOFUTokenDecimals.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";

contract StoxDeploySuitesTest is Test, StoxDeploySuites {
    uint256 constant EIP170_MAX_RUNTIME_CODE_SIZE = 0x6000;

    /// Transcribed from `.github/workflows/manual-sol-artifacts.yaml`, which no
    /// Solidity test can read.
    function dispatchChoices() internal pure returns (string[] memory) {
        string[] memory choices = new string[](25);
        choices[0] = "stox-corporate-actions-facet";
        choices[1] = "stox-receipt";
        choices[2] = "stox-receipt-vault";
        choices[3] = "stox-wrapped-token-vault";
        choices[4] = "stox-wrapped-token-vault-beacon";
        choices[5] = "stox-offchain-asset-receipt-vault-authorizer";
        choices[6] = "stox-offchain-asset-receipt-vault-payment-mint-authorizer";
        choices[7] = "stox-orchestrator";
        choices[8] = "stox-eu-assets-authoriser";
        choices[9] = "stox-corporate-actions-facet@0_1_1";
        choices[10] = "stox-receipt@0_1_1";
        choices[11] = "stox-receipt-vault@0_1_1";
        choices[12] = "stox-wrapped-token-vault@0_1_1";
        choices[13] = "stox-wrapped-token-vault-beacon@0_1_1";
        choices[14] = "stox-wrapped-token-vault-beacon-set-deployer@0_1_1";
        choices[15] = "stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_1";
        choices[16] = "stox-unified-deployer@0_1_1";
        choices[17] = "stox-offchain-asset-receipt-vault-authorizer@0_1_1";
        choices[18] = "stox-offchain-asset-receipt-vault-payment-mint-authorizer@0_1_1";
        choices[19] = "stox-corporate-actions-facet@0_1_30";
        choices[20] = "stox-receipt@0_1_30";
        choices[21] = "stox-receipt-vault@0_1_30";
        choices[22] = "stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_30";
        choices[23] = "stox-orchestrator@0_1_30";
        choices[24] = "stox-orchestrator-beacon-set-deployer@0_1_30";
        return choices;
    }

    function testSuiteKeysAreExactlyTheDispatchChoices() external view {
        DeploySuite[] memory suites = allSuites();
        string[] memory choices = dispatchChoices();
        assertEq(suites.length, choices.length, "a suite is not dispatchable, or a choice is not declared");
        for (uint256 i = 0; i < choices.length; i++) {
            assertEq(suiteByName(choices[i]).suite, choices[i], "dispatch choice is not a declared suite");
        }
    }

    function testArtifactPathsResolveToTheCandidateSource() external view {
        DeployCandidate[] memory candidates = checkedCandidateSuites();
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i].snapshot.mechanism != DeployMechanism.Zoltu) {
                continue;
            }
            assertEq(
                keccak256(vm.getCode(candidates[i].snapshot.artifactPath)),
                keccak256(sourceCreationCode(candidates[i].snapshot.suite)),
                string.concat("artifact path is not this candidate's source: ", candidates[i].snapshot.suite)
            );
        }
    }

    function testDependenciesAreNonZeroAndUnique() external view {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            DeployDependency[] memory deps = suites[i].dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                assertNotEq(deps[j].deployedAddress, address(0), string.concat("zero dependency: ", suites[i].suite));
                for (uint256 k = j + 1; k < deps.length; k++) {
                    assertNotEq(
                        deps[j].deployedAddress,
                        deps[k].deployedAddress,
                        string.concat("repeated dependency: ", suites[i].suite)
                    );
                }
            }
        }
    }

    function testSuitesDependOnTheSiblingsTheyReach() external view {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            bytes memory reach = reachable(suites[i]);
            for (uint256 j = 0; j < suites.length; j++) {
                address sibling = suites[j].storedDeployedAddress;
                if (i == j || sibling == address(0) || sibling == suites[i].storedDeployedAddress) {
                    continue;
                }
                if (!containsAddress(reach, sibling)) {
                    continue;
                }
                assertTrue(
                    containsDependency(suites[i].dependencies, sibling),
                    string.concat(suites[i].suite, " reaches an undeclared sibling: ", suites[j].suite)
                );
            }
        }
    }

    function testSuitesReachEveryDependencyTheyDeclare() external view {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            bytes memory reach = reachable(suites[i]);
            DeployDependency[] memory deps = suites[i].dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                assertTrue(
                    containsAddress(reach, deps[j].deployedAddress),
                    string.concat(
                        suites[i].suite,
                        " declares a dependency it never reaches: ",
                        vm.toString(deps[j].deployedAddress)
                    )
                );
            }
        }
    }

    function externalDeployments() internal pure returns (address[] memory) {
        address[] memory externals = new address[](2);
        externals[0] = CLONE_FACTORY_ADDRESS;
        externals[1] = TOFU_DECIMALS_ADDRESS;
        return externals;
    }

    function testTofuPinIsTheDeploymentSourceReaches() external pure {
        assertEq(TOFU_DECIMALS_ADDRESS, address(LibTOFUTokenDecimals.TOFU_DECIMALS_DEPLOYMENT));
        assertEq(TOFU_DECIMALS_CODEHASH, LibTOFUTokenDecimals.TOFU_DECIMALS_EXPECTED_CODE_HASH);
    }

    function testSuitesDependOnTheExternalsTheyReach() external view {
        DeploySuite[] memory suites = allSuites();
        address[] memory externals = externalDeployments();
        for (uint256 i = 0; i < suites.length; i++) {
            bytes memory reach = reachable(suites[i]);
            for (uint256 j = 0; j < externals.length; j++) {
                if (!containsAddress(reach, externals[j])) {
                    continue;
                }
                assertTrue(
                    containsDependency(suites[i].dependencies, externals[j]),
                    string.concat(
                        suites[i].suite, " reaches an undeclared external deployment: ", vm.toString(externals[j])
                    )
                );
            }
        }
    }

    function testDependencyRuntimeCodeMatchesItsAddress() external view {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            DeployDependency[] memory deps = suites[i].dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                bytes32 expected = bytes32(0);
                if (deps[j].deployedAddress == CLONE_FACTORY_ADDRESS) {
                    expected = CLONE_FACTORY_CODEHASH;
                }
                if (deps[j].deployedAddress == TOFU_DECIMALS_ADDRESS) {
                    expected = TOFU_DECIMALS_CODEHASH;
                }
                for (uint256 k = 0; k < suites.length; k++) {
                    if (
                        suites[k].mechanism == DeployMechanism.Zoltu
                            && deps[j].deployedAddress == suites[k].storedDeployedAddress
                    ) {
                        expected = keccak256(suites[k].storedRuntimeCode);
                    }
                }
                assertNotEq(expected, bytes32(0), string.concat("unknown dependency: ", suites[i].suite));
                assertEq(
                    keccak256(deps[j].runtimeCode),
                    expected,
                    string.concat("dependency runtime code mismatch: ", suites[i].suite)
                );
            }
        }
    }

    function testCandidateRuntimeCodeFitsEip170() external view {
        DeployCandidate[] memory candidates = checkedCandidateSuites();
        for (uint256 i = 0; i < candidates.length; i++) {
            assertLe(
                candidates[i].snapshot.storedRuntimeCode.length,
                EIP170_MAX_RUNTIME_CODE_SIZE,
                string.concat("runtime code over EIP-170: ", candidates[i].snapshot.suite)
            );
        }
    }

    /// Every address a suite's deploy can reach: its creation code, plus the
    /// factory a clone's mechanism data names.
    function reachable(DeploySuite memory suite) internal pure returns (bytes memory) {
        return bytes.concat(suite.creationCode, suite.mechanismData);
    }

    function sourceCreationCode(string memory suite) internal pure returns (bytes memory) {
        bytes32 key = keccak256(bytes(suite));
        if (key == keccak256(bytes(FACET))) return type(StoxCorporateActionsFacet).creationCode;
        if (key == keccak256(bytes(RECEIPT))) return type(StoxReceipt).creationCode;
        if (key == keccak256(bytes(RECEIPT_VAULT))) return type(StoxReceiptVault).creationCode;
        if (key == keccak256(bytes(WRAPPED_TOKEN_VAULT))) return type(StoxWrappedTokenVault).creationCode;
        if (key == keccak256(bytes(WRAPPED_TOKEN_VAULT_BEACON))) return type(StoxWrappedTokenVaultBeacon).creationCode;
        if (key == keccak256(bytes(AUTHORIZER))) return type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode;
        if (key == keccak256(bytes(PAYMENT_MINT_AUTHORIZER))) {
            return type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode;
        }
        if (key == keccak256(bytes(ORCHESTRATOR))) return type(ST0xOrchestrator).creationCode;
        revert(string.concat("no source for suite: ", suite));
    }

    function containsDependency(DeployDependency[] memory deps, address needle) internal pure returns (bool) {
        for (uint256 i = 0; i < deps.length; i++) {
            if (deps[i].deployedAddress == needle) {
                return true;
            }
        }
        return false;
    }

    /// Searches for the leading-zero-stripped address, the immediate solc
    /// emits for a constant address.
    function containsAddress(bytes memory haystack, address needle) internal pure returns (bool) {
        uint256 value = uint256(uint160(needle));
        uint256 width = 0;
        {
            uint256 remaining = value;
            while (remaining != 0) {
                remaining >>= 8;
                width++;
            }
        }
        if (width == 0 || haystack.length < width) {
            return false;
        }
        uint256 shift = 256 - width * 8;
        bytes32 target = bytes32(value << shift);
        bytes32 mask = bytes32(~uint256(0) << shift);
        uint256 last = haystack.length - width;
        for (uint256 i = 0; i <= last; i++) {
            bytes32 window;
            assembly ("memory-safe") {
                window := mload(add(add(haystack, 0x20), i))
            }
            if (window & mask == target) {
                return true;
            }
        }
        return false;
    }
}
