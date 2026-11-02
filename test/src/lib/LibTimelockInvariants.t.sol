// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibTimelockController} from "rain-deploy-0.1.29/src/lib/LibTimelockController.sol";
import {
    BYTECODE_HASH as TIMELOCK_BYTECODE_HASH,
    CREATION_CODE as TIMELOCK_CREATION_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_18/TimelockController.sol";
import {LibTimelockInvariants, UnsupportedChainForGovernanceTimelock} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariantsHarness} from "./LibTimelockInvariantsHarness.sol";

/// @title LibTimelockInvariantsTest
/// @notice Local (non-fork) coverage for what `LibTimelockInvariants` adds to
/// `rain-deploy`'s `LibTimelockController`: the pinned delay, the per-chain
/// pins and their derivation, and the role-id mirrors. The role model's own
/// assertion — no code, other code, other delay, every missing or open role,
/// the proposer as admin — is `LibTimelockController`'s and tested there.
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

    /// @notice The frozen generation the timelocks were deployed from is
    /// consistent: its creation code deploys code hashing to its
    /// `BYTECODE_HASH`.
    function testTimelockGenerationIsConsistent() external {
        LibTimelockController.checkTimelockGeneration(
            vm, TIMELOCK_CREATION_CODE, TIMELOCK_BYTECODE_HASH, LibTimelockInvariants.TIMELOCK_MIN_DELAY, SAFE
        );
    }

    /// @notice A timelock deployed with a different delay is rejected: the
    /// runtime bytecode is identical (delay is storage, not code), so only
    /// the `getMinDelay` pin catches it.
    function testAssertRejectsWrongMinDelay() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address wrongDelay =
            LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(TIMELOCK_CREATION_CODE, 1 hours, SAFE));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMinDelayMismatch.selector,
                wrongDelay,
                LibTimelockInvariants.TIMELOCK_MIN_DELAY,
                1 hours
            )
        );
        harness.callAssertTimelockState(wrongDelay, SAFE);
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
