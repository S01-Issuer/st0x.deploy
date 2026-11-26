// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibTestBlockHeader} from "../lib/LibTestBlockHeader.sol";
import {LibTestZerogTokenCreation} from "../lib/LibTestZerogTokenCreation.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";

/// @title CreateZerogTokensShippedTableTest
/// @notice The shipped 0G token table against the token creation script's derived rows and post-state.
contract CreateZerogTokensShippedTableTest is Test {
    /// @notice Each shipped row is the token the script derives for that row.
    function testShippedTableIsEachRowsCreatedToken() external {
        vm.chainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        CreateZerogTokensHarness script = new CreateZerogTokensHarness("shipped-table");
        TokenInstance[] memory shipped = LibTokenInvariants.productionTokensZerog();
        assertEq(shipped.length, script.callConfigs().length, "one row per config");
        for (uint256 i = 0; i < shipped.length; i++) {
            TokenInstance memory created = script.callToken(i);
            assertEq(shipped[i].underlying, created.underlying, "underlying");
            assertEq(shipped[i].receipt, created.receipt, string.concat(created.underlying, " receipt"));
            assertEq(shipped[i].receiptVault, created.receiptVault, string.concat(created.underlying, " receipt vault"));
            assertEq(
                shipped[i].wrappedTokenVault, created.wrappedTokenVault, string.concat(created.underlying, " wrapper")
            );
        }
    }

    /// @notice On live 0G at the last bundle's block, every row is created and the script's post-state holds.
    function testPostStateHoldsOnLiveZerogAfterTheLastBundle() external {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, LibTestZerogTokenCreation.LAST_BUNDLE_BLOCK);
        // A run's tests share a fork's block env, so another test's warp at this block can leak in.
        vm.warp(LibTestBlockHeader.timestamp(vm.getRawBlockHeader(LibTestZerogTokenCreation.LAST_BUNDLE_BLOCK)));
        CreateZerogTokensHarness script = new CreateZerogTokensHarness("shipped-table-live");
        assertEq(script.callCreatedCount(), LibTokenInvariants.productionTokensZerog().length, "every row created");
        script.callAssertPostState();
    }
}
