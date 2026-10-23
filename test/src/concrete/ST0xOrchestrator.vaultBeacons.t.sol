// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title ST0xOrchestratorVaultBeaconsTest
/// @notice The vault-logic guard checks the beacons the root authority binds
/// on the active chain, so one orchestrator address serves every chain.
contract ST0xOrchestratorVaultBeaconsTest is Test {
    function setUp() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function bindBeacons(address vaultBeacon, address receiptBeacon) internal {
        LibTestDeploy.bind(vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.VAULT_BEACON_NAME, abi.encode(vaultBeacon));
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.RECEIPT_BEACON_NAME, abi.encode(receiptBeacon)
        );
    }

    function serve(address beacon, address implementation) internal {
        vm.mockCall(beacon, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(implementation));
    }

    /// Binds this chain's beacons, serves both chains' beacons the expected
    /// implementations, and Zoltu-deploys the orchestrator.
    function deployOnChain(uint256 chainId, address vaultBeacon, address receiptBeacon, address[4] memory allBeacons)
        internal
        returns (ST0xOrchestrator)
    {
        vm.chainId(chainId);
        bindBeacons(vaultBeacon, receiptBeacon);
        serve(allBeacons[0], LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE);
        serve(allBeacons[1], LibProdDeployV4.STOX_RECEIPT_CANDIDATE);
        serve(allBeacons[2], LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE);
        serve(allBeacons[3], LibProdDeployV4.STOX_RECEIPT_CANDIDATE);
        return ST0xOrchestrator(payable(LibRainDeploy.deployZoltu(type(ST0xOrchestrator).creationCode)));
    }

    /// Two chains binding different beacons get the same orchestrator address,
    /// and each guard follows only its own chain's binding.
    function testEachChainsGuardChecksItsOwnBinding() external {
        address[4] memory beacons = [address(0xA1), address(0xA2), address(0xB1), address(0xB2)];
        uint256 state = vm.snapshotState();

        ST0xOrchestrator onA = deployOnChain(1, beacons[0], beacons[1], beacons);
        assertTrue(onA.vaultLogicIsExpected(), "chain A passes");
        serve(beacons[2], address(0xDEAD));
        assertTrue(onA.vaultLogicIsExpected(), "chain A ignores chain B's beacon");
        serve(beacons[0], address(0xDEAD));
        assertFalse(onA.vaultLogicIsExpected(), "chain A follows its own beacon");

        vm.revertToState(state);
        vm.clearMockedCalls();

        ST0xOrchestrator onB = deployOnChain(8453, beacons[2], beacons[3], beacons);
        assertEq(address(onB), address(onA), "same orchestrator address on both chains");
        assertTrue(onB.vaultLogicIsExpected(), "chain B passes");
        serve(beacons[0], address(0xDEAD));
        assertTrue(onB.vaultLogicIsExpected(), "chain B ignores chain A's beacon");
        serve(beacons[2], address(0xDEAD));
        assertFalse(onB.vaultLogicIsExpected(), "chain B follows its own beacon");
    }

    /// Where the root authority has not bound the vault beacon, the guard
    /// reverts in the registry.
    function testGuardRevertsWhereUnbound() external {
        ST0xOrchestrator orchestrator =
            ST0xOrchestrator(payable(LibRainDeploy.deployZoltu(type(ST0xOrchestrator).creationCode)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME
            )
        );
        orchestrator.vaultLogicIsExpected();
    }
}
