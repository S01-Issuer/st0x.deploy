// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.43/src/lib/LibSafeTx.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";
import {ZerogTokenCreationFixture} from "./ZerogTokenCreationFixture.sol";

/// @title CreateZerogTokensOffZerogRootLineTest
/// @notice Off 0G the bundle is the record alone, right after the backfill. The 0G fixture stands in for HyperEVM: its
/// Safe and timelock are at HyperEVM's pinned addresses, so under HyperEVM's chain id the script reads them through the
/// shared pins.
contract CreateZerogTokensOffZerogRootLineTest is ZerogTokenCreationFixture, RootLineRecordScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new CreateZerogTokensHarness("off-zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.CREATE_ZEROG_TOKENS;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
    }

    function landBeforeOnto() internal override {
        buildZerog();
        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        writeOffBaseHistory(safeAddress());
    }

    function landOnto() internal override {
        LibTestRootLine.write(
            vm,
            safeAddress(),
            LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
            LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS
        );
    }

    function testBundleIsTheRecordAlone() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 1, "bundle length");
    }
}
