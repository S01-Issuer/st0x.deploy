// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeacon} from "../../../src/concrete/ST0xOrchestratorBeacon.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "../../lib/LibTestOrchestratorDeploy.sol";
import {GovernanceTimelockSeatTest} from "../lib/GovernanceTimelockSeatTest.sol";
import {UpgradedImpl} from "./deploy/UpgradedImpl.sol";

contract ST0xOrchestratorBeaconTest is GovernanceTimelockSeatTest {
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("TIMELOCK"))));

    function setUp() public {
        LibRainDeploy.etchZoltuFactory(vm);
        assertEq(
            LibRainDeploy.deployZoltu(type(ST0xOrchestrator).creationCode),
            LibProdDeployCurrent.ST0X_ORCHESTRATOR,
            "orchestrator address"
        );
    }

    function seat() internal override returns (address) {
        return address(new ST0xOrchestratorBeacon());
    }

    function assertSeated(address seated, address timelock) internal view override {
        assertEq(UpgradeableBeacon(seated).implementation(), LibProdDeployCurrent.ST0X_ORCHESTRATOR, "beacon impl");
        assertEq(Ownable(seated).owner(), timelock, "beacon owner");
    }

    function testFuzzConstructorHandsTheBeaconToTheBoundTimelockNotTheSender(address sender, address timelock)
        external
    {
        vm.assume(timelock != address(0) && sender != timelock);
        LibTestDeploy.bindGovernanceTimelock(vm, timelock);
        vm.prank(sender);
        address beacon = address(new ST0xOrchestratorBeacon());
        assertSeated(beacon, timelock);
    }

    function testBeaconUpgradeRedirectsSingleton() external {
        LibTestDeploy.bindGovernanceTimelock(vm, TIMELOCK);
        address beacon = LibRainDeploy.deployZoltu(type(ST0xOrchestratorBeacon).creationCode);
        assertEq(beacon, LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_V2, "beacon address");
        address orchestrator = LibTestOrchestratorDeploy.deployInstance(vm, makeAddr("deployer"));

        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(TIMELOCK);
        UpgradeableBeacon(beacon).upgradeTo(address(newImpl));

        assertEq(UpgradedImpl(orchestrator).TAG(), newImpl.TAG(), "delegates to upgraded impl");
    }

    function testFuzzBeaconUpgradeUnauthorised(address notOwner) external {
        vm.assume(notOwner != TIMELOCK && notOwner != address(0));
        LibTestDeploy.bindGovernanceTimelock(vm, TIMELOCK);
        UpgradeableBeacon beacon = UpgradeableBeacon(address(new ST0xOrchestratorBeacon()));
        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        beacon.upgradeTo(address(newImpl));
    }
}
