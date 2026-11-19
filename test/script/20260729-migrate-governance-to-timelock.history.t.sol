// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {HistoryMigrationScriptTest} from "../lib/HistoryMigrationScriptTest.sol";
import {LibStoxMigrations, NoGovernanceTimelockMigrationOnChain} from "../../src/lib/LibStoxMigrations.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";

contract MigrateGovernanceToTimelockHistoryTest is HistoryMigrationScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new MigrateGovernanceToTimelock());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.GOVERNANCE_TIMELOCK;
    }

    function declaredOnto(uint256 chainId) internal pure override returns (bytes32) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID
            ? LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS
            : LibStoxMigrations.MULTISIG_THRESHOLD;
    }

    /// @dev 0G ran none of the backfilled history, so its record there is record-only.
    function declaredHistory(uint256 chainId) internal pure override returns (bool) {
        return chainId != LibSafeInvariants.ZEROG_CHAIN_ID;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return onDeploymentChain(chainId);
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(NoGovernanceTimelockMigrationOnChain.selector, chainId);
    }
}
