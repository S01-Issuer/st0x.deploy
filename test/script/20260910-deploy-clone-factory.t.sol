// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {
    DeployCloneFactory,
    CloneFactoryAlreadyDeployed,
    ZoltuFactoryMissing
} from "../../script/20260910-deploy-clone-factory.s.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title DeployCloneFactoryTest
/// @notice The frozen creation code must reproduce the pinned CloneFactory
/// (address and codehash) through Zoltu, and the script must refuse a chain
/// that already has it or that has no Zoltu factory.
contract DeployCloneFactoryTest is Test {
    /// @notice On a bare local chain with the Zoltu factory etched, the run
    /// lands the factory at the pin with the pinned codehash — the proof
    /// that the literal is the 0.1.1 creation code. A second run refuses.
    function testFrozenCreationCodeReproducesThePin() external {
        LibRainDeploy.etchZoltuFactory(vm);
        DeployCloneFactory script = new DeployCloneFactory();
        script.run();
        address pinned = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        assertGt(pinned.code.length, 0, "deployed");
        assertEq(pinned.codehash, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH, "codehash");
        vm.expectRevert(abi.encodeWithSelector(CloneFactoryAlreadyDeployed.selector, pinned));
        script.run();
    }

    /// @notice Without the Zoltu factory the deploy cannot be deterministic,
    /// so it refuses before broadcasting.
    function testRefusesWithoutZoltu() external {
        DeployCloneFactory script = new DeployCloneFactory();
        vm.expectRevert(abi.encodeWithSelector(ZoltuFactoryMissing.selector, LibRainDeploy.ZOLTU_FACTORY));
        script.run();
    }

    /// @notice Ethereum already carries the factory at the pin (the July
    /// one-shot), so the script refuses there — the same refusal a re-dispatch
    /// on any bootstrapped chain gets.
    function testRefusesAChainThatHasIt() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        DeployCloneFactory script = new DeployCloneFactory();
        vm.expectRevert(
            abi.encodeWithSelector(
                CloneFactoryAlreadyDeployed.selector, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS
            )
        );
        script.run();
    }
}
