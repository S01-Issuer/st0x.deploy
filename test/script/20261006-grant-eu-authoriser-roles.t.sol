// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.25/src/lib/LibMigrationRegistry.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";

import {
    EuAuthoriserNotDeployed,
    SafeMissingRoleAdmin,
    SafeStillHoldsAdmin,
    grantEuAuthoriserRolesDeclaration
} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {GrantEuAuthoriserRolesHarness} from "./GrantEuAuthoriserRolesHarness.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../../src/lib/LibEuAuthoriserClone.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibStoxMigrations,
    RecordMismatch,
    SafeNotApprovedWriter,
    UnexpectedMigrationLine
} from "../../src/lib/LibStoxMigrations.sol";
import {LibMigrationLineFork} from "../lib/LibMigrationLineFork.sol";

contract GrantEuAuthoriserRolesTest is Test {
    /// @notice Forks `network` with its line at the grant's onto and the Safe
    /// approved to write it.
    /// @param network The fork.
    /// @param tag The artifact tag, unique per test.
    /// @return The harness, or the zero harness when the line already
    /// records the grant.
    function fork(string memory network, string memory tag) internal returns (GrantEuAuthoriserRolesHarness) {
        vm.createSelectFork(network);
        LibMigrationLineFork.approve(vm, LibSafeInvariants.safeForChainId(block.chainid));
        if (LibMigrationLineFork.recordOnto(vm, grantEuAuthoriserRolesDeclaration())) {
            return GrantEuAuthoriserRolesHarness(address(0));
        }
        return new GrantEuAuthoriserRolesHarness(tag);
    }

    function eu() internal view returns (IAccessControl) {
        return IAccessControl(LibEuAuthoriserClone.cloneDeployedAddress(block.chainid));
    }

    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    function map() internal view returns (RoleGrant[] memory) {
        return LibAuthoriserInvariants.expectedEuGrants(
            timelock(), LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
        );
    }

    function testRunRecordsOnlyOnEveryNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            GrantEuAuthoriserRolesHarness script = fork(networks[i], "recordOnly");
            if (address(script) == address(0)) continue;
            SafeTx[] memory txs = script.callAuthorBundle();
            assertEq(txs.length, 1, networks[i]);
            (address registry, bytes memory data) = LibStoxMigrations.recordCall(grantEuAuthoriserRolesDeclaration());
            assertEq(txs[0].to, registry);
            assertEq(txs[0].data, data);
            script.run();
            assertEq(LibStoxMigrations.head(), grantEuAuthoriserRolesDeclaration().id, networks[i]);
        }
    }

    function testRunGrantsMissingRowsAndRenouncesHeldAdmins() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "repair");
        if (address(script) == address(0)) return;
        RoleGrant[] memory rows = map();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        RoleGrant memory missing = rows[LibAuthoriserInvariants.ADMIN_ROLE_COUNT];
        vm.startPrank(timelock());
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            eu().grantRole(rows[i].role, safe);
        }
        eu().revokeRole(missing.role, missing.grantee);
        vm.stopPrank();

        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1 + LibAuthoriserInvariants.ADMIN_ROLE_COUNT + 1);
        assertEq(txs[0].data, abi.encodeCall(IAccessControl.grantRole, (missing.role, missing.grantee)));
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            assertEq(txs[1 + i].data, abi.encodeCall(IAccessControl.renounceRole, (rows[i].role, safe)));
        }
        script.run();
        assertTrue(eu().hasRole(missing.role, missing.grantee));
        assertEq(LibStoxMigrations.head(), grantEuAuthoriserRolesDeclaration().id);
    }

    function testPreflightRefusesAMissingRowTheSafeCannotGrant() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "noAdmin");
        if (address(script) == address(0)) return;
        RoleGrant memory missing = map()[LibAuthoriserInvariants.ADMIN_ROLE_COUNT];
        vm.prank(timelock());
        eu().revokeRole(missing.role, missing.grantee);
        vm.expectRevert(
            abi.encodeWithSelector(SafeMissingRoleAdmin.selector, address(eu()), eu().getRoleAdmin(missing.role))
        );
        script.callPreflight();
    }

    function testPostStateRefusesASafeStillHoldingAnAdmin() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "stillAdmin");
        if (address(script) == address(0)) return;
        script.run();
        bytes32 admin = map()[0].role;
        vm.prank(timelock());
        eu().grantRole(admin, LibSafeInvariants.safeForChainId(block.chainid));
        vm.expectRevert(abi.encodeWithSelector(SafeStillHoldsAdmin.selector, admin));
        script.callAssertPostState();
    }

    function testPreflightRefusesForeignCodeAtTheClone() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "foreignCode");
        if (address(script) == address(0)) return;
        script.callPreflight();
        vm.etch(address(eu()), hex"00");
        vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotDeployed.selector, address(eu())));
        script.callPreflight();
    }

    function testPreflightRefusesAnUnapprovedSafe() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "unapproved");
        if (address(script) == address(0)) return;
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        LibMigrationLineFork.revoke(vm, safe);
        vm.expectRevert(abi.encodeWithSelector(SafeNotApprovedWriter.selector, safe));
        script.callPreflight();
    }

    function testPreflightRefusesAHeadThatIsNotItsOnto() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "wrongHead");
        if (address(script) == address(0)) return;
        script.callPreflight();
        bytes32 other = keccak256("script/not-in-the-line.s.sol");
        vm.prank(LibStoxMigrations.WRITER);
        LibMigrationRegistry.applyMigrationV3(
            LibStoxMigrations.WRITER,
            LibStoxMigrations.NAMESPACE,
            other,
            LibStoxMigrations.onto(grantEuAuthoriserRolesDeclaration().onto)
        );
        assertEq(LibStoxMigrations.head(), other);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, other));
        script.callPreflight();
    }

    function testPostStateRefusesAMissingRecord() external {
        GrantEuAuthoriserRolesHarness script = fork(LibRainDeploy.BASE, "unrecorded");
        if (address(script) == address(0)) return;
        vm.expectRevert(
            abi.encodeWithSelector(RecordMismatch.selector, grantEuAuthoriserRolesDeclaration().id, block.timestamp, 0)
        );
        script.callAssertPostState();
        script.run();
        script.callAssertPostState();
    }
}
