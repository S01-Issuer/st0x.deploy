// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {FleetAlreadyUpgraded, FLEET_UPGRADE_DEADLINE} from "../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
import {UpgradeFleetHarness} from "./UpgradeFleetHarness.sol";
import {LibSafeOps, SafeTx, TxBuilderArtifactMismatch} from "../../src/lib/LibSafeOps.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {ClosureCodehashMismatch} from "../../src/lib/LibClosureInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @notice The fleet-upgrade deadline passed with this chain still pending.
/// Run the outstanding dispatches, extend the deadline, or delete the
/// invariant.
/// @param label The chain still pending.
error FleetUpgradeOverdue(string label);

/// @title UpgradeFleetProdTest
/// @notice PROD coverage for the fleet upgrade: what production IS on each
/// chain, read from a real fork with no mocks, walking the rollout states:
///
/// 1. **Ready** (0.1.30 impls live, beacons on 0.1.1): drives `run()` end to
///    end on the fork — bundle authored and simulated, both beacons land
///    on 0.1.30, EVERY production token's reported state proven unchanged,
///    n+1 downgrade proven; the signer-side `verify` then round-trips the
///    written artifact against the pre-run state, refusing a tampered copy
///    and a wrong build at a target pin.
/// 2. **Executed**: both beacons serve 0.1.30 (asserted directly) and a
///    re-dispatch refuses (`FleetAlreadyUpgraded`).
///
/// State 1 stops passing at `FLEET_UPGRADE_DEADLINE`; state 2 is steady
/// and never expires (until the post-execution pin PR retires this file).
contract UpgradeFleetProdTest is Test {
    /// @notice Walk the active fork's upgrade state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    function assertFleetRollout(string memory label) internal {
        UpgradeFleetHarness script = new UpgradeFleetHarness();
        address[3] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);

        bool upgraded = IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation()
                == LibProdDeployV4.STOX_RECEIPT_0_1_30
            && IBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]).implementation()
                == LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30;
        if (!upgraded) {
            if (block.timestamp >= FLEET_UPGRADE_DEADLINE) {
                revert FleetUpgradeOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: ready - driving the authoring end to end"));
            // Drives the full authoring: simulation flips both beacons on
            // the fork, every token's reported state is proven unchanged,
            // and the n+1 downgrade path is proven. The artifact outlives the
            // state revert, so verify() reads it against the state a signer
            // would see.
            uint256 preRun = vm.snapshotState();
            script.run();
            vm.revertToState(preRun);
            string memory path = script.callArtifactPath();
            script.verify(path);

            (,, SafeTx[] memory txs) = LibSafeOps.parseTxBuilderJson(path);
            txs[0].to = beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX];
            string memory tampered = string.concat(path, ".tampered.json");
            vm.writeFile(
                tampered,
                LibSafeOps.emitTxBuilderJson(
                    LibSafeInvariants.safeForChainId(block.chainid), block.chainid, "tampered", txs
                )
            );
            vm.expectRevert(abi.encodeWithSelector(TxBuilderArtifactMismatch.selector, "firstTarget"));
            script.verify(tampered);

            // The signer-side check gates on the audited targets too.
            vm.etch(LibProdDeployV4.STOX_RECEIPT_0_1_30, hex"fe");
            vm.expectRevert(
                abi.encodeWithSelector(
                    ClosureCodehashMismatch.selector,
                    LibProdDeployV4.STOX_RECEIPT_0_1_30,
                    LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30,
                    keccak256(hex"fe")
                )
            );
            script.verify(path);
            return;
        }

        // Executed steady state.
        assertEq(
            IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation(),
            LibProdDeployV4.STOX_RECEIPT_0_1_30,
            string.concat(label, ": receipt beacon not on 0.1.30")
        );
        assertEq(
            IBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
            string.concat(label, ": receipt-vault beacon not on 0.1.30")
        );
        vm.expectRevert(FleetAlreadyUpgraded.selector);
        script.run();
    }

    function testFleetRolloutBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFleetRollout("base");
    }

    function testFleetRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertFleetRollout("ethereum");
    }

    function testFleetRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertFleetRollout("hyperevm");
    }
}
