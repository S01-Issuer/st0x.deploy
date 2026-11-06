// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeacon} from "../../../src/concrete/ST0xOrchestratorBeacon.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "../../lib/LibTestOrchestratorDeploy.sol";
import {UpgradedImpl} from "./deploy/UpgradedImpl.sol";

contract ST0xOrchestratorBeaconTest is Test {
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("TIMELOCK"))));

    function setUp() public {
        LibRainDeploy.etchZoltuFactory(vm);
        assertEq(
            LibRainDeploy.deployZoltu(type(ST0xOrchestrator).creationCode),
            LibProdDeployCurrent.ST0X_ORCHESTRATOR,
            "orchestrator address"
        );
    }

    function testFuzzConstructorHandsTheBeaconToTheBoundOwnerNotTheSender(
        uint256 chainId,
        address sender,
        address owner
    ) external {
        chainId = bound(chainId, 1, type(uint64).max - 1);
        vm.assume(owner != address(0) && sender != owner);
        vm.chainId(chainId);
        LibTestDeploy.bindBeaconInitialOwner(vm, owner);
        vm.prank(sender);
        address beacon = address(new ST0xOrchestratorBeacon());
        assertEq(UpgradeableBeacon(beacon).implementation(), LibProdDeployCurrent.ST0X_ORCHESTRATOR, "beacon impl");
        assertEq(Ownable(beacon).owner(), owner, "beacon owner");
    }

    /// The orchestrator initial admin does not stand in for the beacon
    /// initial owner.
    function testBeaconOwnerUnboundReverts() external {
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, TIMELOCK);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        new ST0xOrchestratorBeacon();
    }

    function testBeaconOwnerBoundZeroReverts() external {
        LibTestDeploy.bindBeaconInitialOwner(vm, address(0));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ST0xOrchestratorBeacon();
    }

    function testBeaconUpgradeRedirectsSingleton() external {
        LibTestDeploy.bindBeaconInitialOwner(vm, TIMELOCK);
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, TIMELOCK);
        address beacon = LibRainDeploy.deployZoltu(type(ST0xOrchestratorBeacon).creationCode);
        assertEq(beacon, LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON, "beacon address");
        address orchestrator = LibTestOrchestratorDeploy.deployInstance(vm, makeAddr("deployer"));

        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(TIMELOCK);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));

        assertEq(UpgradedImpl(orchestrator).TAG(), newImpl.TAG(), "delegates to upgraded impl");
    }

    function testFuzzBeaconUpgradeUnauthorised(address notOwner) external {
        vm.assume(notOwner != TIMELOCK);
        LibTestDeploy.bindBeaconInitialOwner(vm, TIMELOCK);
        UpgradeableBeacon beacon = UpgradeableBeacon(address(new ST0xOrchestratorBeacon()));
        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        beacon.upgradeTo(address(newImpl));
    }

    function testBeaconUpgradeUnauthorisedFromZero() external {
        LibTestDeploy.bindBeaconInitialOwner(vm, TIMELOCK);
        UpgradeableBeacon beacon = UpgradeableBeacon(address(new ST0xOrchestratorBeacon()));
        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0)));
        beacon.upgradeTo(address(newImpl));
    }
}
