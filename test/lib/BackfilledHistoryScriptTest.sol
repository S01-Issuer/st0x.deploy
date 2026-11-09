// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {HistoryMigrationScriptTest} from "./HistoryMigrationScriptTest.sol";

interface IRunnableScript {
    function run() external;
}

/// @title BackfilledHistoryScriptTest
/// @notice A history migration whose record the V5 backfill writes: `run()`
/// refuses on every chain.
abstract contract BackfilledHistoryScriptTest is HistoryMigrationScriptTest {
    function runRefusal(uint256 chainId) internal pure virtual returns (bytes memory);

    function testRunRefusesOnEveryChain(uint256 chainId) external {
        chainId = bound(chainId, 0, type(uint64).max / 2 - 36);
        vm.chainId(chainId);
        vm.expectRevert(runRefusal(chainId));
        IRunnableScript(sHistoryScript).run();
    }

    function testRunRefusesOnChainZero() external {
        vm.chainId(0);
        vm.expectRevert(runRefusal(0));
        IRunnableScript(sHistoryScript).run();
    }
}
