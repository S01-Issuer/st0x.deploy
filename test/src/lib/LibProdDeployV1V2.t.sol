// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";

/// @title LibProdDeployV1V2Test
/// @notice Verifies V1 and V2 deployments produce the same runtime bytecode
/// (codehash) for unchanged contracts. V1 addresses differ from V2 because
/// V1 was deployed via `new` and V2 uses the Zoltu deterministic factory.
/// StoxWrappedTokenVault is intentionally different between V1 and V2 due to
/// the addition of a ZeroAsset check in initialize(bytes).
contract LibProdDeployV1V2Test is Test {
    /// StoxReceipt V1 and V2 MUST have the same codehash.
    function testStoxReceiptCodehashV1EqualsV2() external pure {
        assertEq(
            LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1, LibProdDeployV2.STOX_RECEIPT_CODEHASH
        );
    }

    /// StoxReceiptVault V1 and V2 MUST have the same codehash.
    function testStoxReceiptVaultCodehashV1EqualsV2() external pure {
        assertEq(
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1,
            LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH
        );
    }

    /// StoxWrappedTokenVault V2 differs from V1 because V2 adds a ZeroAsset
    /// check in initialize(bytes). This is the ONLY source change — verify
    /// the codehashes are NOT equal to confirm the upgrade is reflected.
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
