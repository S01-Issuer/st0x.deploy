// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {LibBeaconInvariants, UnsupportedChainForProdBeacons} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibProdBeacons0_1_1} from "../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdBeaconsBase} from "../../../src/lib/LibProdBeaconsBase.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariantsPerChainHarness} from "./LibBeaconInvariantsPerChainHarness.sol";

contract LibBeaconInvariantsPerChainTest is Test {
    LibBeaconInvariantsPerChainHarness internal lib = new LibBeaconInvariantsPerChainHarness();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testBaseRunsItsV1SetAndEveryOtherDeploymentChainThe011Set() external pure {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(
                LibBeaconInvariants.runsBaseBeaconSet(nets[i].chainId),
                keccak256(bytes(nets[i].name)) == keccak256(bytes(LibRainDeploy.BASE))
            );
        }
    }

    function testUndeployedChainHasNoBeaconSet(uint256 chainId) external {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            vm.assume(chainId != nets[i].chainId);
        }
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForProdBeacons.selector, chainId));
        lib.runsBaseBeaconSet(chainId);
    }

    function testBaseLookupsAreTheBaseLib() external pure {
        uint256 base = LibSafeInvariants.BASE_CHAIN_ID;
        assertEq(LibBeaconInvariants.prodPinnedBeaconsForChainId(base), LibProdBeaconsBase.beacons());
        assertEq(LibBeaconInvariants.prodBeaconSetDeployerForChainId(base), address(0));
        assertEq(LibBeaconInvariants.prodImplementationsForChainId(base), LibProdBeaconsBase.implementations());
        assertEq(LibBeaconInvariants.prodV1ImplementationsForChainId(base), LibProdBeaconsBase.v1Implementations());
    }

    function test011LookupsAreThe011Lib() external pure {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            if (LibBeaconInvariants.runsBaseBeaconSet(id)) continue;
            assertEq(LibBeaconInvariants.prodPinnedBeaconsForChainId(id), LibProdBeacons0_1_1.pinnedBeacons());
            assertEq(LibBeaconInvariants.prodBeaconSetDeployerForChainId(id), LibProdBeacons0_1_1.beaconSetDeployer());
            assertEq(LibBeaconInvariants.prodImplementationsForChainId(id), LibProdBeacons0_1_1.implementations());
            address[4] memory v1 = LibBeaconInvariants.prodV1ImplementationsForChainId(id);
            for (uint256 j = 0; j < v1.length; j++) {
                assertEq(v1[j], address(0));
            }
        }
    }

    function testBaseV1ImplementationsAreTheV1PinsWithNoOrchestrator() external pure {
        address[4] memory v1 = LibProdBeaconsBase.v1Implementations();
        assertTrue(v1[LibBeaconInvariants.RECEIPT_BEACON_INDEX] != address(0));
        assertTrue(v1[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX] != address(0));
        assertTrue(v1[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX] != address(0));
        assertEq(v1[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX], address(0));
        assertTrue(v1[0] != v1[1] && v1[1] != v1[2] && v1[0] != v1[2]);
    }

    function test011PinnedBeaconsLeaveExactlyTheDeployerReadSlotsEmpty() external pure {
        address[4] memory pinned = LibProdBeacons0_1_1.pinnedBeacons();
        assertEq(pinned[LibBeaconInvariants.RECEIPT_BEACON_INDEX], address(0));
        assertEq(pinned[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], address(0));
        assertTrue(pinned[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX] != address(0));
        assertTrue(pinned[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX] != address(0));
        assertTrue(LibProdBeacons0_1_1.beaconSetDeployer() != address(0));
    }

    /// The receipt and receipt-vault beacons serve the 0.1.30 impls the fleet upgrade
    /// (`20260825-upgrade-fleet-to-0-1-30`) put behind them on every chain; the wrapped-token-vault beacon still
    /// serves 0.1.1 and the orchestrator beacon the 0.1.30 orchestrator (`LibOrchestratorInvariants.assertBeaconSet`).
    function testExpectedImplementationsAreTheFleetUpgradeImplsAndTheBootstrapRest() external pure {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(nets[i].chainId);
            assertEq(impls[LibBeaconInvariants.RECEIPT_BEACON_INDEX], LibProdDeployV4.STOX_RECEIPT_0_1_30);
            assertEq(impls[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30);
            assertEq(
                impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1
            );
            assertEq(impls[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX], LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30);
        }
    }

    function testUndeployedChainHasNoExpectedImplementations(uint256 chainId) external {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            vm.assume(chainId != nets[i].chainId);
        }
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForProdBeacons.selector, chainId));
        lib.prodExpectedImplementationsForChainId(chainId);
    }

    function assertEq(address[4] memory a, address[4] memory b) internal pure {
        for (uint256 i = 0; i < a.length; i++) {
            assertEq(a[i], b[i]);
        }
    }
}
