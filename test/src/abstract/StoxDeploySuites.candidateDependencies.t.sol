// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {DEPENDENCIES as ATTEST_SUB_PARSER_DEPENDENCIES} from "../../../src/generated/candidate/St0xAttestSubParser.sol";
import {DEPENDENCIES as ORCHESTRATOR_DEPENDENCIES} from "../../../src/generated/candidate/ST0xOrchestrator.sol";
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
    function checkStoredDependencies(string memory key, bytes memory stored) internal view {
        (DeploySuite memory suite, bool found) = candidateOf(declaration(), key);
        assertTrue(found, key);
        assertEq(abi.encode(suite.dependencies), stored, key);
    }

    function testCandidateDependenciesAreTheDeclaredOnes() external view {
        checkStoredDependencies(ATTEST_SUB_PARSER, ATTEST_SUB_PARSER_DEPENDENCIES);
        checkStoredDependencies(ORCHESTRATOR, ORCHESTRATOR_DEPENDENCIES);
        checkStoredDependencies(FACET, FACET_DEPENDENCIES);
        checkStoredDependencies(GOVERNANCE_TIMELOCK, GOVERNANCE_TIMELOCK_DEPENDENCIES);
        checkStoredDependencies(AUTHORIZER, AUTHORIZER_DEPENDENCIES);
        checkStoredDependencies(PAYMENT_MINT_AUTHORIZER, PAYMENT_MINT_AUTHORIZER_DEPENDENCIES);
        checkStoredDependencies(RECEIPT_BEACON, RECEIPT_BEACON_DEPENDENCIES);
        checkStoredDependencies(RECEIPT, RECEIPT_DEPENDENCIES);
        checkStoredDependencies(RECEIPT_VAULT_BEACON, RECEIPT_VAULT_BEACON_DEPENDENCIES);
        checkStoredDependencies(RECEIPT_VAULT, RECEIPT_VAULT_DEPENDENCIES);
        checkStoredDependencies(WRAPPED_TOKEN_VAULT_BEACON, WRAPPED_TOKEN_VAULT_BEACON_DEPENDENCIES);
        checkStoredDependencies(WRAPPED_TOKEN_VAULT, WRAPPED_TOKEN_VAULT_DEPENDENCIES);
    }
}
