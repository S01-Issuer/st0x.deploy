// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {
    LibTimelockInvariants,
    UnsupportedChainForGovernanceTimelock,
    TimelockNotDeployed,
    TimelockCodehashMismatch,
    TimelockMinDelayMismatch,
    TimelockMissingRole,
    TimelockUnexpectedRole
} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariantsHarness} from "./LibTimelockInvariantsHarness.sol";

/// @title LibTimelockInvariantsTest
/// @notice Local (non-fork) coverage for `LibTimelockInvariants`: the Zoltu
/// address derivation is validated against the REAL factory bytecode (etched
/// locally), the state assertion is exercised green against a
/// pinned-configuration deploy and red against every deviation class —
/// missing code, alien code, wrong delay, missing role, open role, and a
/// root-admin escalation path.
contract LibTimelockInvariantsTest is Test {
    /// @notice Stand-in for a chain's token-owner Safe; the invariants only
    /// read role membership for it.
    address internal constant SAFE = address(0x5aFe00000000000000000000000000000000aAaa);

    LibTimelockInvariantsHarness internal harness;

    function setUp() external {
        harness = new LibTimelockInvariantsHarness();
    }

    /// @notice Deploy a timelock through the real (etched) Zoltu factory
    /// from the pinned init code, as the deploy broadcast does.
    function deployPinnedTimelock() internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        return LibRainDeploy.deployZoltu(LibTimelockInvariants.timelockInitCode(SAFE));
    }

    /// @notice The in-source CREATE2 derivation lands where the real Zoltu
    /// factory deploys the same init code.
    function testExpectedAddressMatchesRealZoltuFactory() external {
        address deployed = deployPinnedTimelock();
        assertEq(deployed, LibTimelockInvariants.expectedTimelockAddress(SAFE));
    }

    /// @notice Distinct Safes derive distinct timelock addresses: the
    /// constructor arguments are part of the init code.
    function testExpectedAddressVariesWithSafe() external pure {
        assertNotEq(
            LibTimelockInvariants.expectedTimelockAddress(SAFE),
            LibTimelockInvariants.expectedTimelockAddress(address(0xBEEF))
        );
    }

    /// @notice The full state assertion passes against a fresh
    /// pinned-configuration deploy.
    function testAssertTimelockStatePasses() external {
        address timelock = deployPinnedTimelock();
        LibTimelockInvariants.assertTimelockState(timelock, SAFE);
    }

    /// @notice The role-hash mirrors match the live OZ getters, so invariant
    /// call sites can name roles without a deployed instance.
    function testRoleMirrorsMatchLiveGetters() external {
        TimelockController timelock = TimelockController(payable(deployPinnedTimelock()));
        assertEq(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, timelock.PROPOSER_ROLE());
        assertEq(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, timelock.EXECUTOR_ROLE());
        assertEq(LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE, timelock.CANCELLER_ROLE());
        assertEq(LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE, timelock.DEFAULT_ADMIN_ROLE());
    }

    /// @notice The pinned delay is 48 hours and the pinned deploy carries it.
    function testMinDelayPin() external {
        TimelockController timelock = TimelockController(payable(deployPinnedTimelock()));
        assertEq(LibTimelockInvariants.TIMELOCK_MIN_DELAY, 48 hours);
        assertEq(timelock.getMinDelay(), LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    /// @notice An address without code is rejected before any call into it.
    function testAssertRejectsUndeployed() external {
        address missing = LibTimelockInvariants.expectedTimelockAddress(SAFE);
        vm.expectRevert(abi.encodeWithSelector(TimelockNotDeployed.selector, missing));
        harness.callAssertTimelockState(missing, SAFE);
    }

    /// @notice The frozen creation-code and runtime-codehash pins match the
    /// OZ dependency as the current profile compiles it.
    function testTimelockPinsMatchCompiledDependency() external pure {
        assertEq(
            keccak256(LibTimelockInvariants.TIMELOCK_CREATION_CODE), keccak256(type(TimelockController).creationCode)
        );
        assertEq(LibTimelockInvariants.TIMELOCK_RUNTIME_CODEHASH, keccak256(type(TimelockController).runtimeCode));
    }

    /// @notice Alien bytecode at the timelock address is rejected by the
    /// codehash pin before any role read is trusted.
    function testAssertRejectsWrongCodehash() external {
        address timelock = deployPinnedTimelock();
        vm.etch(timelock, hex"600160005260206000f3");
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockCodehashMismatch.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_RUNTIME_CODEHASH,
                timelock.codehash
            )
        );
        harness.callAssertTimelockState(timelock, SAFE);
    }

    /// @notice A timelock deployed with a different delay is rejected: the
    /// runtime bytecode is identical (delay is storage, not code), so only
    /// the `getMinDelay` pin catches it.
    function testAssertRejectsWrongMinDelay() external {
        address[] memory principals = new address[](1);
        principals[0] = SAFE;
        TimelockController wrongDelay = new TimelockController(1 hours, principals, principals, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockMinDelayMismatch.selector,
                address(wrongDelay),
                LibTimelockInvariants.TIMELOCK_MIN_DELAY,
                1 hours
            )
        );
        harness.callAssertTimelockState(address(wrongDelay), SAFE);
    }

    /// @notice A missing grant on ANY required role — the Safe's proposer,
    /// canceller, and executor, and the timelock's own root admin — trips
    /// the missing `(role, account)` pair, walked per role: revoke, assert
    /// the typed revert, re-grant, and check the restored state passes.
    /// Self-administration goes last and is not restored: once the timelock
    /// renounces its own root admin no principal can re-grant it.
    function testAssertRejectsEveryMissingRole() external {
        address timelock = deployPinnedTimelock();
        // EXECUTOR is not among them: execution is permissionless, so the
        // Safe never holds that role and revoking it from the Safe is a
        // no-op. The executor requirement is pinned by
        // `testAssertRejectsClosedExecutorRole` against the zero address.
        bytes32[2] memory safeRoles =
            [LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE];
        for (uint256 i = 0; i < safeRoles.length; i++) {
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(safeRoles[i], SAFE);
            vm.expectRevert(abi.encodeWithSelector(TimelockMissingRole.selector, timelock, safeRoles[i], SAFE));
            harness.callAssertTimelockState(timelock, SAFE);
            vm.prank(timelock);
            IAccessControl(timelock).grantRole(safeRoles[i], SAFE);
            harness.callAssertTimelockState(timelock, SAFE);
        }

        vm.prank(timelock);
        IAccessControl(timelock).revokeRole(LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE, timelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockMissingRole.selector, timelock, LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE, timelock
            )
        );
        harness.callAssertTimelockState(timelock, SAFE);
    }

    /// @notice A zero-address grant on any role that must stay CLOSED — OZ's
    /// `onlyRoleOrOpenRole` treats `hasRole(role, address(0))` as "open to
    /// everyone" — is rejected, walked per role: proposer, canceller and root
    /// admin each trip their own typed revert, and the closed state passes
    /// again after each revoke. Simulated through the timelock's own
    /// self-administration path.
    /// @dev EXECUTOR is excluded: execution is permissionless, so an open
    /// executor is the required state, pinned by
    /// `testAssertRejectsClosedExecutorRole` below.
    function testAssertRejectsEveryOpenRole() external {
        address timelock = deployPinnedTimelock();
        bytes32[3] memory roles = [
            LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
            LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE,
            LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.prank(timelock);
            IAccessControl(timelock).grantRole(roles[i], address(0));
            vm.expectRevert(abi.encodeWithSelector(TimelockUnexpectedRole.selector, timelock, roles[i], address(0)));
            harness.callAssertTimelockState(timelock, SAFE);
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(roles[i], address(0));
        }
        // Every zero-grant revoked: the closed state passes again.
        harness.callAssertTimelockState(timelock, SAFE);
    }

    /// @notice A caller holding no role executes a matured operation and
    /// the operation's effect lands. Schedule (Safe) → warp out the 48h
    /// delay → execute (anon) → the scheduled self-administration grant is
    /// live and the operation is `Done`.
    function testAnonExecutesMaturedOperation() external {
        TimelockController timelock = TimelockController(payable(deployPinnedTimelock()));
        address anon = address(0xA904);
        address newCanceller = address(0xCACE);

        bytes memory data =
            abi.encodeCall(IAccessControl.grantRole, (LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE, newCanceller));
        bytes32 salt = keccak256("anon-executes-matured-operation");
        bytes32 id = timelock.hashOperation(address(timelock), 0, data, bytes32(0), salt);

        vm.prank(SAFE);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        assertTrue(timelock.isOperationPending(id), "operation must be pending after schedule");
        assertFalse(timelock.isOperationReady(id), "operation must not be executable inside the delay");

        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(anon);
        timelock.execute(address(timelock), 0, data, bytes32(0), salt);

        assertTrue(timelock.isOperationDone(id), "anon execution must complete the operation");
        assertTrue(
            IAccessControl(address(timelock)).hasRole(LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE, newCanceller),
            "the executed operation's effect must land"
        );
    }

    /// @notice The roleless anon that can execute can neither schedule nor
    /// cancel — each attempt reverts with OZ's missing-role error naming the
    /// role gate it hit.
    function testAnonCannotScheduleOrCancel() external {
        TimelockController timelock = TimelockController(payable(deployPinnedTimelock()));
        address anon = address(0xA904);
        bytes memory data =
            abi.encodeCall(IAccessControl.grantRole, (LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE, anon));
        bytes32 salt = keccak256("anon-cannot-schedule-or-cancel");

        vm.prank(anon);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                anon,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE
            )
        );
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY);

        vm.prank(SAFE);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        bytes32 id = timelock.hashOperation(address(timelock), 0, data, bytes32(0), salt);

        vm.prank(anon);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                anon,
                LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE
            )
        );
        timelock.cancel(id);
        assertTrue(timelock.isOperationPending(id), "the anon cancel attempt must not have removed the operation");
    }

    /// @notice A closed executor role is rejected. Asserted by revoking
    /// `EXECUTOR_ROLE` from the zero address on an otherwise-pinned timelock.
    function testAssertRejectsClosedExecutorRole() external {
        address timelock = deployPinnedTimelock();
        vm.prank(timelock);
        IAccessControl(timelock).revokeRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockMissingRole.selector, timelock, LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(0)
            )
        );
        harness.callAssertTimelockState(timelock, SAFE);
    }

    /// @notice A Safe holding `DEFAULT_ADMIN_ROLE` is rejected. Simulated by
    /// deploying with the optional constructor admin set to the Safe.
    function testAssertRejectsSafeAsRootAdmin() external {
        address[] memory principals = new address[](1);
        principals[0] = SAFE;
        TimelockController adminned =
            new TimelockController(LibTimelockInvariants.TIMELOCK_MIN_DELAY, principals, principals, SAFE);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUnexpectedRole.selector,
                address(adminned),
                LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE,
                SAFE
            )
        );
        harness.callAssertTimelockState(address(adminned), SAFE);
    }

    /// @notice Chain selection returns the per-chain pin for the supported
    /// chains and reverts (never falls back) for anything else.
    function testTimelockForChainId() external {
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK
        );
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM
        );
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForGovernanceTimelock.selector, uint256(31337)));
        harness.callTimelockForChainId(31337);
    }

    /// @notice Every per-chain pin equals the Zoltu address derived from the
    /// frozen creation code and that chain's Safe; a zeroed or drifted pin
    /// fails here.
    function testPinsMatchDerivedAddresses() external pure {
        assertEq(
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE)
        );
        assertEq(
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM,
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM)
        );
        assertEq(
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM,
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM)
        );
        assertEq(
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD,
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD)
        );
        assertEq(
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC,
            LibTimelockInvariants.expectedTimelockAddress(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC)
        );
    }

    /// @notice Every chain with a pinned token-owner Safe resolves through
    /// `timelockForChainId` rather than reverting.
    function testEveryPinnedChainResolves() external pure {
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK
        );
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM
        );
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.HYPEREVM_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM
        );
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ROBINHOOD_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD
        );
        assertEq(
            LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BSC_CHAIN_ID),
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC
        );
    }
}
