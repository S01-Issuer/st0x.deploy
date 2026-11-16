// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibInvariants} from "../../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// @title LibInvariantsTest
/// @notice The composed production-state bundles pass against each chain's
/// production state built locally.
contract LibInvariantsTest is Test {
    /// @notice Base's bundle passes for Base's Safe with its owners in
    /// `expectedOwners()` order.
    function testAssertAllPassesOnLocalBase() external {
        LibLocalProdState.build(vm, LibSafeInvariants.BASE_CHAIN_ID);
        LibInvariants.assertAll(Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE)));
    }

    /// @notice On every chain the multichain bundle passes for that chain's
    /// token table and US authoriser.
    function testAssertProductionStatePassesOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.build(vm, chainIds[i]);
            LibInvariants.assertProductionState(
                LibTokenInvariants.productionTokensForChainId(chainIds[i]),
                LibAuthoriserInvariants.authoriserForChainId(chainIds[i])
            );
            vm.revertToState(snapshot);
        }
    }
}
