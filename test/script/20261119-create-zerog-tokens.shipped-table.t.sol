// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";

/// @title CreateZerogTokensShippedTableTest
/// @notice The shipped 0G token table is what the token creation made: row `i` is the receipt and vault the 0.1.1
/// receipt-vault beacon-set deployer made at row `i`'s nonces and the wrapper the wrapper deployer made at its own,
/// and on live 0G after the last bundle the script's own post-state holds for every row it derives that way.
contract CreateZerogTokensShippedTableTest is Test {
    /// @notice The block of Safe nonce 5, the last creation bundle, tx
    /// 0xe6872cd5302397d09aaa0d68b00e04e1f348ec13e720e519900118b555e25862.
    uint256 internal constant ZEROG_LAST_BUNDLE_BLOCK = 51156480;

    /// @notice Each shipped row is the token the script derives for that row from the deployers' nonces.
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

    /// @notice On live 0G right after the last bundle, the deployers made exactly the 65 rows, the migration is
    /// recorded, and every row passes the script's post-state: wired, on its region's authoriser, owned by the
    /// timelock, named from its config, and the last bundle's rows empty.
    function testPostStateHoldsOnLiveZerogAfterTheLastBundle() external {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, ZEROG_LAST_BUNDLE_BLOCK);
        CreateZerogTokensHarness script = new CreateZerogTokensHarness("shipped-table-live");
        assertEq(script.callCreatedCount(), LibTokenInvariants.productionTokensZerog().length, "every row created");
        script.callAssertPostState();
    }
}
