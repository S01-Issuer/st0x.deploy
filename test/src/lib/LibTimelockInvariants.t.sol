// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
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
    /// @notice Stand-in for a chain's token-owner Safe. The invariants only
    /// read role membership for this address, so a plain EOA-style address
    /// is sufficient locally.
    address internal constant SAFE = address(0x5aFe00000000000000000000000000000000aAaa);

    LibTimelockInvariantsHarness internal harness;

    function setUp() external {
        harness = new LibTimelockInvariantsHarness();
    }

    /// @notice Deploy a timelock through the real (etched) Zoltu factory
    /// from the pinned init code, exactly as the deploy broadcast does.
    function deployPinnedTimelock() internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        return LibRainDeploy.deployZoltu(LibTimelockInvariants.timelockInitCode(SAFE));
    }

    /// @notice The in-source CREATE2 derivation must land exactly where the
    /// real Zoltu factory deploys the same init code — this is the equality
    /// the deploy script's address assertion and the future pin PR both
    /// stand on.
    function testExpectedAddressMatchesRealZoltuFactory() external {
        address deployed = deployPinnedTimelock();
        assertEq(deployed, LibTimelockInvariants.expectedTimelockAddress(SAFE));
    }

    /// @notice Distinct Safes must derive distinct timelock addresses — the
    /// constructor arguments are part of the init code, so per-chain Safes
    /// produce per-chain timelocks by construction.
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
    /// version-locked OZ dependency as the current profile compiles it. Red
    /// here means the compiler settings or the dependency moved past the
    /// pinned generation: regenerate the pins only while no chain has
    /// deployed or migrated onto them; once production carries the pinned
    /// generation the pins stand (they describe prod, not source) and the
    /// divergence is a deliberate new-generation decision.
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
    /// the exact missing `(role, account)` pair, walked per role: revoke,
    /// assert the typed revert, re-grant, and prove the restored state
    /// passes. Self-administration goes last and is not restored: once the
    /// timelock renounces its own root admin no principal can re-grant it,
    /// which is exactly why the invariant pins it.
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
    /// self-administration path, proving the pinned deploy COULD drift here
    /// only via a (timelocked) governance action that this invariant would
    /// then flag.
    /// @dev EXECUTOR is deliberately excluded: execution is permissionless,
    /// so an open executor is the REQUIRED state, pinned by
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
        // Every zero-grant revoked: the closed state passes again, proving
        // each rejection above was the zero-grant and nothing else.
        harness.callAssertTimelockState(timelock, SAFE);
    }

    /// @notice Execution is permissionless END-TO-END, not just as a role
    /// bit: a caller holding no role at all executes a matured operation and
    /// the operation's effect lands. Schedule (Safe) → warp out the 48h
    /// delay → execute (anon) → the scheduled self-administration grant is
    /// live and the operation is `Done`. This is the behavioural proof of
    /// the property the open-executor state assert pins; without it the
    /// property rests only on OZ's `onlyRoleOrOpenRole` semantics being what
    /// the assert assumes.
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

    /// @notice The asymmetry is the design: execution is open, scheduling
    /// and vetoing stay privileged. The same roleless anon that can execute
    /// can neither schedule nor cancel — each attempt reverts with OZ's
    /// missing-role error naming the exact role gate it hit.
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

    /// @notice A CLOSED executor role is rejected. Execution is deliberately
    /// permissionless, so revoking the open grant would put the operator back
    /// in the path as a censor of matured operations — the exact property
    /// Clearstar asked us to remove. Asserted by revoking `EXECUTOR_ROLE`
    /// from the zero address on an otherwise-pinned timelock.
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

    /// @notice A Safe holding `DEFAULT_ADMIN_ROLE` is rejected — root admin
    /// on the proposer would let it re-grant roles instantly, bypassing the
    /// delay entirely. Simulated by deploying with the optional constructor
    /// admin set to the Safe.
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
    /// frozen creation code and that chain's Safe — UNCONDITIONALLY. The
    /// not-zero guards that let this test ride through the hydration window
    /// are retired with it: all three deploys have executed and the pins are
    /// deploy history, so a zeroed or drifted pin must fail loudly here
    /// rather than silently skip. A future chain's placeholder phase gets
    /// its own guarded branch when its arm is added; these three never go
    /// back.
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
    }

    /// @notice Every chain with a pinned token-owner Safe resolves through
    /// `timelockForChainId` rather than reverting. The chain-coverage guard
    /// in `GovernanceTimelockMigration.t.sol` enforces this against the
    /// live Safe map; this pins the three chains explicitly so a dropped
    /// arm fails here too, next to the constants it would have dropped.
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
    }
}
