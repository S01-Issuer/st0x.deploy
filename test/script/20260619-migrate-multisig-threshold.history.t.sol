// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    MigrateMultisigThreshold,
    NoMultisigThresholdMigrationOnChain
} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {HistoryMigrationScriptTest} from "../lib/HistoryMigrationScriptTest.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract MigrateMultisigThresholdHistoryTest is HistoryMigrationScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new MigrateMultisigThreshold());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.MULTISIG_THRESHOLD;
    }

    function declaredOnto(uint256) internal pure override returns (bytes32) {
        return MIGRATION_HEAD_GENESIS;
    }

    function declaredHistory(uint256) internal pure override returns (bool) {
        return true;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return onDeploymentChain(chainId);
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(NoMultisigThresholdMigrationOnChain.selector, chainId);
    }
}
