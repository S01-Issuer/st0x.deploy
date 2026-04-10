// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";

/// @title LibProdDeployV1V2Test
/// @notice Compares V1 and V2 codehashes for the deployed contracts. The V1
/// addresses were deployed via `new`; V2 uses the Zoltu deterministic
/// factory.
///
/// As of the corporate-actions stack (PRs #18–#25) and the receipt
/// coordination follow-up (PR #7), both `StoxReceipt` and `StoxReceiptVault`
/// have gained new behaviour relative to V1 — lazy rebase migration,
/// cursor tracking, and direct-storage writes — so their codehashes
/// intentionally differ from V1. Per `CLAUDE.md` §Versioning, this drift
/// SHOULD be reflected in a new production version heading (V3 / a new
/// `LibProdDeployV3`) once the stack merges; until that bump lands the
/// `LibProdDeployV2.STOX_RECEIPT*_CODEHASH` constants in the pointer files
/// describe the as-built post-stack contracts rather than the historical
/// V2 deployment. The tests below assert the EXPECTED drift against V1 —
/// if any of them flip to equality, either a regression has silently
/// reverted the stack's functionality or someone has re-pinned V2 to V1
/// without bumping to a new version.
contract LibProdDeployV1V2Test is Test {
    /// StoxReceipt V1 differs from V2: V2 (post-PR #7) adds lazy rebase
    /// migration via `_update` and `balanceOf` overrides, plus the
    /// `LibCorporateActionReceipt` storage cursor and `LibERC1155Storage`
    /// direct-write path.
    function testStoxReceiptCodehashV1DiffersV2() external pure {
        assertTrue(
            LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1 != LibProdDeployV2.STOX_RECEIPT_CODEHASH,
            "StoxReceipt V1 codehash must differ from V2 post-rebase"
        );
    }

    /// StoxReceiptVault V1 differs from V2: V2 (post-PR stack) adds the
    /// corporate-action facet delegatecall path, lazy share-side rebase
    /// via `_update`, the `balanceOf` / `totalSupply` overrides, and
    /// per-cursor pot accounting.
    function testStoxReceiptVaultCodehashV1DiffersV2() external pure {
        assertTrue(
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
                != LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH,
            "StoxReceiptVault V1 codehash must differ from V2 post-rebase"
        );
    }

    /// StoxWrappedTokenVault V2 differs from V1 because V2 adds a ZeroAsset
    /// check in initialize(bytes). This was the only pre-corporate-actions
    /// source change — the test pre-dates this PR stack and still holds.
    function testStoxWrappedTokenVaultCodehashV1DiffersV2() external pure {
        assertTrue(
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
                != LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH
        );
    }

    /// StoxUnifiedDeployer V2 differs from V1 because V2 references V2
    /// deployer addresses instead of V1. Verify codehashes are NOT equal.
    function testStoxUnifiedDeployerCodehashV1DiffersV2() external pure {
        assertTrue(
            LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1
                != LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH
        );
    }
}
