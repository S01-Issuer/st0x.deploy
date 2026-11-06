// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";

import {
    GrantEuAuthoriserRoles,
    GrantEuAuthoriserRolesRecordedByBackfill,
    NoGrantEuAuthoriserRolesOnChain
} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";

contract GrantEuAuthoriserRolesTest is Test {
    function chains() internal pure returns (uint256[5] memory) {
        return [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
    }

    function testDeclarationIsHistoryOntoTheGovernanceTimelock(uint256 chainId) external {
        ScriptDeclaration memory declared = new GrantEuAuthoriserRoles().declaration(chainId);
        assertEq(declared.id, LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES);
        assertEq(declared.onto, LibStoxMigrations.GOVERNANCE_TIMELOCK);
        assertTrue(declared.history);
    }

    function testExecutedAtRevertsOffItsChains(uint256 chainId) external {
        uint256[5] memory known = chains();
        for (uint256 i = 0; i < known.length; i++) {
            vm.assume(chainId != known[i]);
        }
        GrantEuAuthoriserRoles script = new GrantEuAuthoriserRoles();
        vm.expectRevert(abi.encodeWithSelector(NoGrantEuAuthoriserRolesOnChain.selector, chainId));
        script.executedAt(chainId);
    }

    function testHistoryAtExecutedAtLandsOnTheGovernanceTimelockRecord(uint256 index) external {
        uint256 chainId = chains()[bound(index, 0, 4)];
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

    function testRunRefusesBecauseTheBackfillWritesTheRecord(uint256 chainId) external {
        chainId = bound(chainId, 0, type(uint64).max / 2 - 36);
        vm.chainId(chainId);
        GrantEuAuthoriserRoles script = new GrantEuAuthoriserRoles();
        vm.expectRevert(abi.encodeWithSelector(GrantEuAuthoriserRolesRecordedByBackfill.selector, chainId));
        script.run();
    }

    function testRunRefusesOnChainZero() external {
        vm.chainId(0);
        GrantEuAuthoriserRoles script = new GrantEuAuthoriserRoles();
        vm.expectRevert(abi.encodeWithSelector(GrantEuAuthoriserRolesRecordedByBackfill.selector, uint256(0)));
        script.run();
    }
}
