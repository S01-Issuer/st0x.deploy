// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.18/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.18/src/lib/LibSafeFork.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {PostMigrationProbeImpl} from "./PostMigrationProbeImpl.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title PostMigrationGovernanceTest
/// @notice The governance loop, proven against the CURRENT state of a chain the
/// migration has already executed on.
///
/// Every other proof of the loop runs from the PRE-migration state: the
/// migration script's own `_proveGovernanceLoop` fires while authoring, and
/// `testBeaconUpgradeRunsThroughTimelock` and friends rewind the executed
/// migration before driving it. None of them answer the question that matters
/// once the bundle has landed: with the timelock now holding the beacons and
/// the `_ADMIN` roles, can the Safe still drive an upgrade through it, and can
/// it no longer drive one directly?
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

        address safeAddr = LibSafeInvariants.safeForChainId(block.chainid);
        address timelockAddr = LibTimelockInvariants.timelockForChainId(block.chainid);

        // EVERY in-use beacon, not a representative one. Upgrading these is the
        // escape hatch: if even one of the four cannot be driven through the
        // timelock, that surface is frozen for as long as the timelock owns it.
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);

        // Precondition: this chain HAS migrated. If it has not, this test
        // reports that rather than passing.
        for (uint256 i = 0; i < beacons.length; i++) {
            assertEq(Ownable(beacons[i]).owner(), timelockAddr, "beacon is not timelock-owned: chain has not migrated");
        }

        _driveBeaconUpgrades(Safe(payable(safeAddr)), timelockAddr, beacons, "post-migration-loop");
    }

    /// Drive a real upgrade of EVERY beacon through the timelock, and assert
    /// the Safe cannot do it directly.
    /// @param safe The chain's token-owner Safe.
    /// @param timelockAddr The chain's governance timelock.
    /// @param beacons Every in-use production beacon.
    /// @param tag Salt discriminator, so two proofs on one chain cannot collide.
    function _driveBeaconUpgrades(Safe safe, address timelockAddr, address[4] memory beacons, string memory tag)
        internal
    {
        // Deployed AFTER the fork switch: a contract deployed before it does
        // not exist on the fork that is then selected.
        probeImpl = new PostMigrationProbeImpl();

        address safeAddr = address(safe);
        TimelockController controller = TimelockController(payable(timelockAddr));

        // `simulateNPlus1` gates on the Safe's live threshold, so pin it.
        LibSafe.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        for (uint256 i = 0; i < beacons.length; i++) {
            address beacon = beacons[i];
            address implBefore = IBeacon(beacon).implementation();

            // (2) The Safe lost the direct path. Asserted by calling as the Safe.
            vm.prank(safeAddr);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safeAddr));
            UpgradeableBeacon(beacon).upgradeTo(implBefore);

            // The destination must DIFFER from the incumbent or step (5) cannot
            // tell an executed upgrade from a no-op.
            assertTrue(address(probeImpl) != implBefore, "probe impl collided with the incumbent");

            // (3) Schedule through the Safe's real signature-verified exec path,
            // at the production threshold — not a prank, so the threshold gate
            // is part of what is proven. The salt carries the index so four
            // operations on one chain cannot collide.
            bytes memory action = abi.encodeCall(UpgradeableBeacon.upgradeTo, (address(probeImpl)));
            bytes32 salt = keccak256(abi.encodePacked(tag, block.chainid, i));
            bytes32 id = controller.hashOperation(beacon, 0, action, bytes32(0), salt);
            LibSafeFork.simulateNPlus1(
                vm,
                safe,
                timelockAddr,
                abi.encodeCall(
                    TimelockController.schedule,
                    (beacon, 0, action, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
                )
            );

            // (4) Inside the window: pending, and NOT executable. A timelock
            // that let this through would be a timelock in name only.
            assertTrue(controller.isOperationPending(id), "schedule did not register");
            assertFalse(controller.isOperationReady(id), "executable inside the delay");

            // (5) After the delay: executable, and the execution lands.
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            assertTrue(controller.isOperationReady(id), "not executable after the delay");
            LibSafeFork.simulateNPlus1(
                vm,
                safe,
                timelockAddr,
                abi.encodeCall(TimelockController.execute, (beacon, 0, action, bytes32(0), salt))
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
        Safe safe = Safe(payable(safeAddr));
        TimelockController controller = TimelockController(payable(timelockAddr));
        address beacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];

        LibSafe.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        bytes memory action = abi.encodeCall(UpgradeableBeacon.upgradeTo, (IBeacon(beacon).implementation()));
        bytes32 salt = keccak256(abi.encodePacked("post-migration-cancel", block.chainid));
        bytes32 id = controller.hashOperation(beacon, 0, action, bytes32(0), salt);
        LibSafeFork.simulateNPlus1(
            vm,
            safe,
            timelockAddr,
            abi.encodeCall(
                TimelockController.schedule,
                (beacon, 0, action, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            )
        );
        assertTrue(controller.isOperationPending(id), "schedule did not register");

        LibSafeFork.simulateNPlus1(vm, safe, timelockAddr, abi.encodeCall(TimelockController.cancel, (id)));
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
