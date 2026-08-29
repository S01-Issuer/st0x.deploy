// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {
    UpgradeFleetTo0_1_30,
    UpgradeTargetNotDeployed,
    FleetAlreadyUpgraded,
    FLEET_UPGRADE_DEADLINE
} from "../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
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
/// 1. **Targets pending** (every chain today): the 0.1.30 impls are not
///    deployed — `run()` refuses `UpgradeTargetNotDeployed`, pinning that
///    the closure suites come first.
/// 2. **Ready** (targets live, beacons on 0.1.1): drives `run()` end to
///    end on the fork — bundle authored and simulated, both beacons land
///    on 0.1.30, EVERY production token's reported state proven unchanged,
///    n+1 downgrade proven.
/// 3. **Executed**: both beacons serve 0.1.30 (asserted directly) and a
///    re-dispatch refuses (`FleetAlreadyUpgraded`).
///
/// States 1–2 stop passing at `FLEET_UPGRADE_DEADLINE`; state 3 is steady
/// and never expires (until the post-execution pin PR retires this file).
contract UpgradeFleetProdTest is Test {
    /// @notice Walk the active fork's upgrade state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    function assertFleetRollout(string memory label) internal {
        UpgradeFleetTo0_1_30 script = new UpgradeFleetTo0_1_30();
        address receiptBeacon = LibBeaconInvariants.receiptBeaconForChainId(block.chainid);
        address receiptVaultBeacon = LibBeaconInvariants.receiptVaultBeaconForChainId(block.chainid);

        bool targetsLive = LibProdDeployV4.STOX_RECEIPT_0_1_30.code.length != 0
            && LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30.code.length != 0
            && LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30.code.length != 0;
        if (!targetsLive) {
            if (block.timestamp >= FLEET_UPGRADE_DEADLINE) {
                revert FleetUpgradeOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: 0.1.30 impls not deployed - fleet upgrade blocked"));
            console2.log("-> dispatch the manual-sol-artifacts-0-1-30 suites first");
            vm.expectRevert(
                abi.encodeWithSelector(UpgradeTargetNotDeployed.selector, LibProdDeployV4.STOX_RECEIPT_0_1_30)
            );
            script.run();
            return;
        }

        bool upgraded = IBeacon(receiptBeacon).implementation() == LibProdDeployV4.STOX_RECEIPT_0_1_30
            && IBeacon(receiptVaultBeacon).implementation() == LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30;
        if (!upgraded) {
            if (block.timestamp >= FLEET_UPGRADE_DEADLINE) {
                revert FleetUpgradeOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: ready - driving the authoring end to end"));
            // Drives the full authoring: simulation flips both beacons on
            // the fork, every token's reported state is proven unchanged,
            // and the n+1 downgrade path is proven.
            script.run();
            return;
        }

        // Executed steady state.
        assertEq(
            IBeacon(receiptBeacon).implementation(),
            LibProdDeployV4.STOX_RECEIPT_0_1_30,
            string.concat(label, ": receipt beacon not on 0.1.30")
        );
        assertEq(
            IBeacon(receiptVaultBeacon).implementation(),
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
