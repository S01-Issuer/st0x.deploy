// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC165} from "@openzeppelin-contracts-5.7.0/utils/introspection/IERC165.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.29/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibConfigRegistryDeploy.sol";

import {ST0xOrchestratorBeaconSetDeployer} from "../../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {UpgradedImpl} from "./UpgradedImpl.sol";
import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {LibStoxConfig, ZeroGovernanceTimelock} from "../../../../src/lib/LibStoxConfig.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {IST0xOrchestratorBeaconSetDeployerV2} from "../../../../src/interface/IST0xOrchestratorBeaconSetDeployerV2.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {GovernanceTimelockSeatTest} from "../../lib/GovernanceTimelockSeatTest.sol";

contract ST0xOrchestratorBeaconSetDeployerTest is GovernanceTimelockSeatTest {
    // ERC-1967 beacon slot.
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// The governance timelock the tests not about resolving it bind.
    address internal constant TIMELOCK = address(uint160(uint256(keccak256("TIMELOCK"))));

    ST0xOrchestrator internal impl;

    function setUp() public {
        impl = new ST0xOrchestrator();
        // The Zoltu deployer hardcodes the beacon implementation to the fixed
        // production impl address (`ST0X_ORCHESTRATOR_CANDIDATE`), so etch
        // the freshly-built orchestrator runtime there — the beacon requires
        // code at that address, and `deploy` delegatecalls it via the proxy.
        vm.etch(LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, address(impl).code);
    }

    function seat() internal override returns (address) {
        return address(new ST0xOrchestratorBeaconSetDeployer());
    }

    /// The beacon serves the candidate orchestrator and is owned by
    /// `timelock`.
    function assertSeated(address seated, address timelock) internal view override {
        IBeacon beacon = ST0xOrchestratorBeaconSetDeployer(seated).iOrchestratorBeacon();
        assertEq(beacon.implementation(), LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, "beacon impl");
        assertEq(Ownable(address(beacon)).owner(), timelock, "beacon owner");
    }

    function _deployer() internal returns (ST0xOrchestratorBeaconSetDeployer) {
        LibTestDeploy.bindGovernanceTimelock(vm, TIMELOCK);
        return new ST0xOrchestratorBeaconSetDeployer();
    }

    /// The account constructing the deployer never owns the beacon: the
    /// bound timelock does.
    function testFuzzConstructorHandsTheBeaconToTheBoundTimelockNotTheSender(address sender, address timelock)
        external
    {
        vm.assume(timelock != address(0) && sender != timelock);
        LibTestDeploy.bindGovernanceTimelock(vm, timelock);
        vm.prank(sender);
        ST0xOrchestratorBeaconSetDeployer d = new ST0xOrchestratorBeaconSetDeployer();
        assertSeated(address(d), timelock);
    }

    /// The caller does not choose the owner: on any chain the deployed
    /// instance's admin is the bound timelock, whoever calls.
    function testFuzzDeploySeatsTheBoundTimelockOnAnyChain(uint256 chainId, address timelock, address caller)
        external
    {
        chainId = bound(chainId, 1, type(uint64).max - 1);
        vm.assume(timelock != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != timelock);
        vm.chainId(chainId);
        LibTestDeploy.bindGovernanceTimelock(vm, timelock);
        ST0xOrchestratorBeaconSetDeployer d = new ST0xOrchestratorBeaconSetDeployer();
        IBeacon beacon = d.iOrchestratorBeacon();

        vm.recordLogs();
        vm.prank(caller);
        address orchestrator = d.deploy();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(orchestrator != address(0), "non-zero");
        assertGt(orchestrator.code.length, 0, "has code");
        // Bound to the beacon.
        assertEq(address(uint160(uint256(vm.load(orchestrator, BEACON_SLOT)))), address(beacon), "beacon slot");
        // The timelock holds DEFAULT_ADMIN_ROLE; not vault-bound (singleton).
        ST0xOrchestrator o = ST0xOrchestrator(payable(orchestrator));
        assertTrue(o.hasRole(0x00, timelock), "timelock is admin");
        assertFalse(o.hasRole(0x00, caller), "caller not admin");

        // Deployment(sender, orchestrator, owner) — sender+orchestrator indexed, owner in data.
        bytes32 sig = keccak256("Deployment(address,address,address)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(d) && logs[i].topics.length == 3 && logs[i].topics[0] == sig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), caller, "sender topic");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), orchestrator, "orchestrator topic");
                assertEq(abi.decode(logs[i].data, (address)), timelock, "owner data");
            }
        }
        assertTrue(found, "Deployment emitted");
    }

    /// `deploy` resolves the timelock again, so a root rebind to zero after
    /// construction leaves nothing to seat.
    function testDeployRefusesARebindToAZeroTimelock() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        LibTestDeploy.bindGovernanceTimelock(vm, address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroGovernanceTimelock.selector));
        d.deploy();
    }

    function testFuzzDeployRefusesARebindToAValueTypeOtherThanAddress(string memory valueType) external {
        vm.assume(bytes(valueType).length > 0 && keccak256(bytes(valueType)) != keccak256("address"));
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, valueType, abi.encode(TIMELOCK)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME,
                keccak256("address"),
                keccak256(bytes(valueType))
            )
        );
        d.deploy();
    }

    function testFuzzDeployRefusesOtherCodeAtTheRegistry(bytes memory code) external {
        vm.assume(code.length > 0 && keccak256(code) != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        vm.etch(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, code);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        d.deploy();
    }

    /// Two deploys give two proxies under the same owner: the owner is not
    /// what distinguishes them.
    function testDeployMultipleDistinct() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        address a = d.deploy();
        address b = d.deploy();
        assertTrue(a != b, "distinct proxies");
        assertTrue(ST0xOrchestrator(payable(a)).hasRole(0x00, TIMELOCK), "first seats the timelock");
        assertTrue(ST0xOrchestrator(payable(b)).hasRole(0x00, TIMELOCK), "second seats the timelock");
    }

    function testBeaconUpgradeRedirectsSingleton() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        address orchestrator = d.deploy();

        UpgradedImpl newImpl = new UpgradedImpl();
        // The beacon owner is the bound timelock, not a deploy param.
        vm.prank(TIMELOCK);
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));

        // Call through the proxy proves live delegation to the new impl.
        assertEq(UpgradedImpl(orchestrator).TAG(), 0xBEEF, "delegates to upgraded impl");
    }

    function testFuzzBeaconUpgradeUnauthorised(address notOwner) external {
        vm.assume(notOwner != TIMELOCK && notOwner != address(0));
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));
    }

    function testSupportsInterface() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        // Both advertised interfaces report true.
        assertTrue(d.supportsInterface(type(IST0xOrchestratorBeaconSetDeployerV2).interfaceId), "V2");
        assertTrue(d.supportsInterface(type(IERC165).interfaceId), "IERC165");
        // ERC-165 requires the 0xffffffff sentinel to always be unsupported.
        assertFalse(d.supportsInterface(0xffffffff), "0xffffffff");
    }

    /// No false positives: every interface id other than the two advertised
    /// ones must report unsupported.
    function testFuzzSupportsInterfaceRejectsOthers(bytes4 badInterfaceId) external {
        vm.assume(badInterfaceId != type(IST0xOrchestratorBeaconSetDeployerV2).interfaceId);
        vm.assume(badInterfaceId != type(IERC165).interfaceId);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        assertFalse(d.supportsInterface(badInterfaceId), "no false positive");
    }
}
