// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";

import {
    GrantEuAuthoriserRoles,
    GrantEuAuthoriserRolesRecordedByBackfill,
    NoGrantEuAuthoriserRolesOnChain
} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {BackfilledHistoryScriptTest} from "../lib/BackfilledHistoryScriptTest.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";

contract GrantEuAuthoriserRolesTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new GrantEuAuthoriserRoles());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES;
    }

    function declaredOnto(uint256) internal pure override returns (bytes32) {
        return LibStoxMigrations.GOVERNANCE_TIMELOCK;
    }

    function declaredHistory(uint256) internal pure override returns (bool) {
        return true;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return onDeploymentChain(chainId);
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(NoGrantEuAuthoriserRolesOnChain.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(GrantEuAuthoriserRolesRecordedByBackfill.selector, chainId);
    }

    function testHistoryAtExecutedAtLandsOnTheGovernanceTimelockRecord(uint256 index) external {
        uint256[5] memory chains = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        uint256 chainId = chains[bound(index, 0, 4)];
        uint256 executedAt = new GrantEuAuthoriserRoles().executedAt(chainId);
        address safe = makeAddr("safe");
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, safe);

        vm.warp(new MigrateGovernanceToTimelock().executedAt(chainId));
        LibTestRootLine.write(vm, safe, LibStoxMigrations.GOVERNANCE_TIMELOCK, MIGRATION_HEAD_GENESIS);
        vm.warp(executedAt + 1 days);

        (address to, bytes memory data) =
            LibStoxMigrations.historyCall(new GrantEuAuthoriserRoles().declaration(chainId), executedAt);
        vm.prank(safe);
        (bool ok,) = to.call(data);
        assertTrue(ok);

        assertEq(LibStoxMigrations.applied(LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES), executedAt);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES);
    }
}
