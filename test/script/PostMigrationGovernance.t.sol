// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";

import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeOps} from "../../src/lib/LibSafeOps.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title PostMigrationGovernanceTest
/// @notice The governance loop, proven against the CURRENT state of a chain the
/// migration has already executed on.
///
/// Every existing proof of the loop runs from the PRE-migration state: the
/// migration script's own `_proveGovernanceLoop` fires while authoring, and
/// `testBeaconUpgradeRunsThroughTimelock` and friends fork Base, which has not
/// migrated. None of them answer the question that matters once the bundle has
/// landed: with the timelock now holding the beacons and the `_ADMIN` roles, can
/// the Safe still drive an upgrade through it, and can it no longer drive one
/// directly?
///
/// Forks are taken at `latest`, so these assert what is true NOW rather than at
/// a pinned block. That is the point — a pinned block could not have observed
/// the migration.
contract PostMigrationGovernanceTest is Test {
    /// A destination for the proving upgrade that is NOT the implementation the
    /// beacon already points at. `upgradeTo` only requires a contract, and
    /// upgrading to the incumbent leaves the final assertion holding whether the
    /// operation executed or did nothing at all.
    PostMigrationProbeImpl internal probeImpl;

    /// Prove the full loop on one already-migrated chain:
    /// 1. the timelock, not the Safe, owns the beacon (the migration landed);
    /// 2. the Safe can no longer upgrade it directly;
    /// 3. the Safe CAN schedule an upgrade through the timelock;
    /// 4. the operation is not executable inside the delay;
    /// 5. after the delay it executes and the implementation actually moves.
    function _assertGovernanceUsable(string memory network) internal {
        vm.createSelectFork(network);

        // Deployed AFTER the fork switch: a contract deployed before it does
        // not exist on the fork that is then selected.
        probeImpl = new PostMigrationProbeImpl();

        address safeAddr = LibSafeInvariants.safeForChainId(block.chainid);
        address timelockAddr = LibTimelockInvariants.timelockForChainId(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        TimelockController controller = TimelockController(payable(timelockAddr));

        // EVERY in-use beacon, not a representative one. Upgrading these is the
        // escape hatch: if even one of the four cannot be driven through the
        // timelock, that surface is frozen for as long as the timelock owns it.
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);

        for (uint256 i = 0; i < beacons.length; i++) {
            address beacon = beacons[i];

            // (1) Precondition: this chain HAS migrated. If it has not, this
            // test is being run against the wrong chain and must say so rather
            // than pass.
            assertEq(Ownable(beacon).owner(), timelockAddr, "beacon is not timelock-owned: chain has not migrated");

            address implBefore = IBeacon(beacon).implementation();

            // (2) The Safe lost the direct path. Asserted by calling as the Safe.
            vm.prank(safeAddr);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safeAddr));
            UpgradeableBeacon(beacon).upgradeTo(implBefore);

            // The destination must DIFFER from the incumbent or step (5) cannot
            // tell an executed upgrade from a no-op.
            assertTrue(address(probeImpl) != implBefore, "probe impl collided with the incumbent");

            // (3) Schedule through the Safe's real signature-verified exec path,
            // at the production threshold — not a prank, so the 3-of-6 gate is
            // part of what is proven. The salt carries the index so four
            // operations on one chain cannot collide.
            bytes memory action = abi.encodeCall(UpgradeableBeacon.upgradeTo, (address(probeImpl)));
            bytes32 salt = keccak256(abi.encodePacked("post-migration-loop", block.chainid, i));
            bytes32 id = controller.hashOperation(beacon, 0, action, bytes32(0), salt);
            LibSafeOps.simulateNPlus1(
                safe,
                timelockAddr,
                abi.encodeCall(
                    TimelockController.schedule,
                    (beacon, 0, action, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
                ),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );

            // (4) Inside the window: pending, and NOT executable. A timelock
            // that let this through would be a timelock in name only.
            assertTrue(controller.isOperationPending(id), "schedule did not register");
            assertFalse(controller.isOperationReady(id), "executable inside the delay");

            // (5) After the delay: executable, and the execution lands.
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            assertTrue(controller.isOperationReady(id), "not executable after the delay");
            LibSafeOps.simulateNPlus1(
                safe,
                timelockAddr,
                abi.encodeCall(TimelockController.execute, (beacon, 0, action, bytes32(0), salt)),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
            assertTrue(controller.isOperationDone(id), "operation did not complete");
            // The beacon MOVED. Asserting it still equals `implBefore` would
            // hold just as well if nothing had executed at all.
            assertEq(IBeacon(beacon).implementation(), address(probeImpl), "implementation did not land");
            assertTrue(IBeacon(beacon).implementation() != implBefore, "implementation did not move");
        }
    }

    /// The Safe must also be able to VETO inside the window, or a mistaken
    /// schedule is unstoppable for 48h.
    function _assertCancelUsable(string memory network) internal {
        vm.createSelectFork(network);
        address safeAddr = LibSafeInvariants.safeForChainId(block.chainid);
        address timelockAddr = LibTimelockInvariants.timelockForChainId(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        TimelockController controller = TimelockController(payable(timelockAddr));
        address beacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];

        bytes memory action = abi.encodeCall(UpgradeableBeacon.upgradeTo, (IBeacon(beacon).implementation()));
        bytes32 salt = keccak256(abi.encodePacked("post-migration-cancel", block.chainid));
        bytes32 id = controller.hashOperation(beacon, 0, action, bytes32(0), salt);
        LibSafeOps.simulateNPlus1(
            safe,
            timelockAddr,
            abi.encodeCall(
                TimelockController.schedule,
                (beacon, 0, action, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            ),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        assertTrue(controller.isOperationPending(id), "schedule did not register");

        LibSafeOps.simulateNPlus1(
            safe,
            timelockAddr,
            abi.encodeCall(TimelockController.cancel, (id)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        assertFalse(controller.isOperationPending(id), "cancel did not clear the operation");
    }

    function testGovernanceUsableOnEthereum() external {
        _assertGovernanceUsable(LibStoxDeployNetworks.ETHEREUM);
    }

    function testGovernanceUsableOnHyperevm() external {
        _assertGovernanceUsable(LibStoxDeployNetworks.HYPEREVM);
    }

    function testCancelUsableOnEthereum() external {
        _assertCancelUsable(LibStoxDeployNetworks.ETHEREUM);
    }

    function testCancelUsableOnHyperevm() external {
        _assertCancelUsable(LibStoxDeployNetworks.HYPEREVM);
    }

    function testGovernanceUsableOnBase() external {
        _assertGovernanceUsable(LibRainDeploy.BASE);
    }

    function testGovernanceUsableOnRobinhood() external {
        _assertGovernanceUsable(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testGovernanceUsableOnBsc() external {
        _assertGovernanceUsable(LibStoxDeployNetworks.BSC);
    }

    function testCancelUsableOnBase() external {
        _assertCancelUsable(LibRainDeploy.BASE);
    }

    function testCancelUsableOnRobinhood() external {
        _assertCancelUsable(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testCancelUsableOnBsc() external {
        _assertCancelUsable(LibStoxDeployNetworks.BSC);
    }
}

/// An upgrade destination with no behaviour of its own. `UpgradeableBeacon`
/// requires only that the new implementation is a contract, and the test needs
/// an address that is provably NOT the one the beacon already points at — what
/// the implementation does is irrelevant to proving the loop ran.
contract PostMigrationProbeImpl {}
