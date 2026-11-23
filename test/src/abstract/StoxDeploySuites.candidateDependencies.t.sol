// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeploySuite
} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {DEPENDENCIES as ATTEST_SUB_PARSER_DEPENDENCIES} from "../../../src/generated/candidate/St0xAttestSubParser.sol";
import {DEPENDENCIES as ORCHESTRATOR_DEPENDENCIES} from "../../../src/generated/candidate/ST0xOrchestrator.sol";
import {
    DEPENDENCIES as ORCHESTRATOR_BEACON_DEPENDENCIES
} from "../../../src/generated/candidate/ST0xOrchestratorBeacon.sol";
import {DEPENDENCIES as FACET_DEPENDENCIES} from "../../../src/generated/candidate/StoxCorporateActionsFacet.sol";
import {
    DEPENDENCIES as GOVERNANCE_TIMELOCK_DEPENDENCIES
} from "../../../src/generated/candidate/StoxGovernanceTimelock.sol";
import {
    DEPENDENCIES as AUTHORIZER_DEPENDENCIES
} from "../../../src/generated/candidate/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    DEPENDENCIES as PAYMENT_MINT_AUTHORIZER_DEPENDENCIES
} from "../../../src/generated/candidate/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {DEPENDENCIES as RECEIPT_BEACON_DEPENDENCIES} from "../../../src/generated/candidate/StoxReceiptBeacon.sol";
import {DEPENDENCIES as RECEIPT_DEPENDENCIES} from "../../../src/generated/candidate/StoxReceipt.sol";
import {
    DEPENDENCIES as RECEIPT_VAULT_BEACON_DEPENDENCIES
} from "../../../src/generated/candidate/StoxReceiptVaultBeacon.sol";
import {DEPENDENCIES as RECEIPT_VAULT_DEPENDENCIES} from "../../../src/generated/candidate/StoxReceiptVault.sol";
import {
    DEPENDENCIES as WRAPPED_TOKEN_VAULT_BEACON_DEPENDENCIES
} from "../../../src/generated/candidate/StoxWrappedTokenVaultBeacon.sol";
import {
    DEPENDENCIES as WRAPPED_TOKEN_VAULT_DEPENDENCIES
} from "../../../src/generated/candidate/StoxWrappedTokenVault.sol";

/// @title StoxDeploySuitesCandidateDependenciesTest
/// @notice Each candidate snapshot's stored `DEPENDENCIES` are exactly the dependencies its suite declares.
/// `script/cut-release.sh` freezes these bytes as a release's record of what must be on a network before broadcast.
contract StoxDeploySuitesCandidateDependenciesTest is Test, StoxDeploySuites {
    function checkStoredDependencies(DeployDeclaration memory declared, string memory key, bytes memory stored)
        internal
        pure
    {
        (DeploySuite memory suite, bool found) = candidateOf(declared, key);
        assertTrue(found, key);
        assertEq(abi.encode(suite.dependencies), stored, key);
    }

    /// Every candidate in `candidateSuites()` has a stored snapshot here, so a new candidate fails until it is listed.
    function testCandidateDependenciesAreTheDeclaredOnes() external view {
        string[13] memory keys = [
            ATTEST_SUB_PARSER,
            ORCHESTRATOR,
            ORCHESTRATOR_BEACON,
            FACET,
            GOVERNANCE_TIMELOCK,
            AUTHORIZER,
            PAYMENT_MINT_AUTHORIZER,
            RECEIPT_BEACON,
            RECEIPT,
            RECEIPT_VAULT_BEACON,
            RECEIPT_VAULT,
            WRAPPED_TOKEN_VAULT_BEACON,
            WRAPPED_TOKEN_VAULT
        ];
        bytes[13] memory stored = [
            ATTEST_SUB_PARSER_DEPENDENCIES,
            ORCHESTRATOR_DEPENDENCIES,
            ORCHESTRATOR_BEACON_DEPENDENCIES,
            FACET_DEPENDENCIES,
            GOVERNANCE_TIMELOCK_DEPENDENCIES,
            AUTHORIZER_DEPENDENCIES,
            PAYMENT_MINT_AUTHORIZER_DEPENDENCIES,
            RECEIPT_BEACON_DEPENDENCIES,
            RECEIPT_DEPENDENCIES,
            RECEIPT_VAULT_BEACON_DEPENDENCIES,
            RECEIPT_VAULT_DEPENDENCIES,
            WRAPPED_TOKEN_VAULT_BEACON_DEPENDENCIES,
            WRAPPED_TOKEN_VAULT_DEPENDENCIES
        ];
        DeployCandidate[] memory candidates = candidateSuites();
        assertEq(candidates.length, keys.length, "every candidate is checked");
        DeployDeclaration memory declared = declaration();
        for (uint256 i = 0; i < candidates.length; i++) {
            string memory key = candidates[i].snapshot.suite;
            uint256 matches = 0;
            for (uint256 j = 0; j < keys.length; j++) {
                if (keccak256(bytes(keys[j])) == keccak256(bytes(key))) {
                    matches++;
                    checkStoredDependencies(declared, key, stored[j]);
                }
            }
            assertEq(matches, 1, key);
        }
    }
}
