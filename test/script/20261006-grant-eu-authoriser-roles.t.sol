// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibMigrationRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {
    GrantEuAuthoriserRoles,
    GrantEuAuthoriserRolesAlreadyApplied,
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

    function lastTx(address safe) internal returns (SafeTx memory) {
        SafeTx[] memory txs = new GrantEuAuthoriserRoles().grantBundle(makeAddr("clone"), safe, makeAddr("timelock"));
        return txs[txs.length - 1];
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

    function testBundleEndsWithTheRootLineRecordOntoTheGovernanceTimelock() external {
        LibTestRootLine.etchRegistry(vm);
        SafeTx memory record = lastTx(makeAddr("safe"));

        assertEq(record.to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(record.value, 0);
        assertEq(uint8(record.operation), uint8(Enum.Operation.Call));
        assertEq(
            record.data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationV5,
                (
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES,
                    LibMigrationRegistry.onto(
                        LibRegistryAuthority.ROOT_AUTHORITY,
                        LibStoxMigrations.NAMESPACE,
                        LibStoxMigrations.GOVERNANCE_TIMELOCK
                    ),
                    ""
                )
            )
        );
    }

    function testBundleRecordSentByTheSafeLandsOnTheRootLine() external {
        address safe = makeAddr("safe");
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, safe);
        LibTestRootLine.write(vm, safe, LibStoxMigrations.GOVERNANCE_TIMELOCK, MIGRATION_HEAD_GENESIS);
        vm.warp(1_800_000_000);
        SafeTx memory record = lastTx(safe);

        vm.prank(safe);
        (bool ok,) = record.to.call(record.data);
        assertTrue(ok);

        assertEq(LibStoxMigrations.applied(LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES), 1_800_000_000);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES);
    }

    function testBundleRecordRefusedBeforeTheGovernanceTimelockRecord() external {
        address safe = makeAddr("safe");
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, safe);
        SafeTx memory record = lastTx(safe);

        vm.prank(safe);
        (bool ok, bytes memory err) = record.to.call(record.data);
        assertFalse(ok);
        assertEq(
            err,
            abi.encodeWithSelector(
                IMigrationRegistryV5.UnexpectedMigrationHead.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxMigrations.NAMESPACE,
                LibStoxMigrations.GOVERNANCE_TIMELOCK,
                MIGRATION_HEAD_GENESIS
            )
        );
    }

    function testRunRefusesWhenAlreadyRecorded() external {
        address safe = makeAddr("safe");
        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, safe);
        LibTestRootLine.write(vm, safe, LibStoxMigrations.GOVERNANCE_TIMELOCK, MIGRATION_HEAD_GENESIS);
        LibTestRootLine.write(
            vm, safe, LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES, LibStoxMigrations.GOVERNANCE_TIMELOCK
        );

        GrantEuAuthoriserRoles script = new GrantEuAuthoriserRoles();
        vm.expectRevert(GrantEuAuthoriserRolesAlreadyApplied.selector);
        script.run();
    }
}
