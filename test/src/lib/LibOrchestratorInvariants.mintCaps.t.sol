// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";

import {
    ST0xOrchestrator,
    ORCHESTRATOR_MINT_ROLE,
    ORCHESTRATOR_MINT_ADMIN_ROLE,
    ORCHESTRATOR_BURN_ROLE,
    ORCHESTRATOR_BURN_ADMIN_ROLE,
    ORCHESTRATOR_EMERGENCY_ROLE,
    ORCHESTRATOR_EMERGENCY_ADMIN_ROLE
} from "../../../src/concrete/ST0xOrchestrator.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {BeaconOwnerMismatch, BeaconImplementationMismatch} from "../../../src/lib/LibBeaconInvariants.sol";
import {
    LibOrchestratorInvariants,
    OrchestratorSetDeployerMissing,
    OrchestratorInstanceMissing,
    OrchestratorRoleMissing,
    OrchestratorUnexpectedRoleHolder,
    OrchestratorRoleAdminUnexpected
} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibOrchestratorInvariantsHarness} from "./LibOrchestratorInvariantsHarness.sol";

/// @title LibOrchestratorInvariantsTest
/// @notice The mint-caps orchestrator invariants against a local deploy that
/// matches production: the current-release orchestrator and beacon-set
/// deployer Zoltu-deployed on Base, then the first `deploy()`. Green on that
/// deploy, and each holder, wiring or address deviation reverts with its
/// own typed error.
contract LibOrchestratorInvariantsMintCapsTest is Test {
    /// @notice Stand-in for the chain's token-owner Safe; the invariants only
    /// read its role membership.
    address internal constant SAFE = address(0x5aFe00000000000000000000000000000000aAaa);

    /// @notice OZ `AccessControlUpgradeable`'s ERC-7201 storage slot.
    bytes32 internal constant ACCESS_CONTROL_SLOT = 0x02dd7bc7dec4dceedda775e58dd541e08a116c6c53815c0bd028192f7b626800;

    LibOrchestratorInvariantsHarness internal harness;
    address internal timelock;
    address internal deployKey;
    ST0xOrchestratorBeaconSetDeployer internal setDeployer;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new LibOrchestratorInvariantsHarness();
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        deployKey = LibProdDeployCurrent.BEACON_INITIAL_OWNER;

        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(ST0xOrchestrator).creationCode);
        setDeployer = ST0xOrchestratorBeaconSetDeployer(
            LibRainDeploy.deployZoltu(type(ST0xOrchestratorBeaconSetDeployer).creationCode)
        );
    }

    function deployInstance() internal returns (IAccessControl) {
        return IAccessControl(setDeployer.deploy());
    }

    function adminRoles() internal pure returns (bytes32[4] memory) {
        return [
            // DEFAULT_ADMIN_ROLE is 0x00 in OZ AccessControl.
            bytes32(0), ORCHESTRATOR_MINT_ADMIN_ROLE, ORCHESTRATOR_BURN_ADMIN_ROLE, ORCHESTRATOR_EMERGENCY_ADMIN_ROLE
        ];
    }

    function operatingRoles() internal pure returns (bytes32[3] memory) {
        return [ORCHESTRATOR_MINT_ROLE, ORCHESTRATOR_BURN_ROLE, ORCHESTRATOR_EMERGENCY_ROLE];
    }

    /// @notice Overwrite `role`'s admin role in the instance's AccessControl
    /// storage: `RoleData { mapping hasRole; bytes32 adminRole; }`.
    function setRoleAdmin(address instance, bytes32 role, bytes32 adminRole) internal {
        bytes32 roleData = keccak256(abi.encode(role, ACCESS_CONTROL_SLOT));
        vm.store(instance, bytes32(uint256(roleData) + 1), adminRole);
    }

    /// @notice The derived beacon and instance are where the production
    /// deployer actually creates them.
    function testMintCapsAddressesMatchDeploy() external {
        assertEq(address(setDeployer), LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER, "set deployer");
        assertEq(address(setDeployer.iOrchestratorBeacon()), LibOrchestratorInvariants.mintCapsBeacon(), "beacon");
        assertEq(address(deployInstance()), LibOrchestratorInvariants.mintCapsInstance(), "instance");
    }

    function testAssertMintCapsBeaconSetPasses() external view {
        harness.callAssertMintCapsBeaconSet();
    }

    function testAssertMintCapsBeaconSetRevertsWhenDeployerMissing() external {
        vm.etch(address(setDeployer), "");
        vm.expectRevert(abi.encodeWithSelector(OrchestratorSetDeployerMissing.selector, address(setDeployer)));
        harness.callAssertMintCapsBeaconSet();
    }

    /// @notice A beacon handed to anyone but the timelock fails, the deploy
    /// key included.
    function testFuzzAssertMintCapsBeaconSetRevertsOnOtherOwner(address owner) external {
        vm.assume(owner != timelock && owner != address(0));
        address beacon = LibOrchestratorInvariants.mintCapsBeacon();
        vm.prank(timelock);
        UpgradeableBeacon(beacon).transferOwnership(owner);
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerMismatch.selector, beacon, timelock, owner));
        harness.callAssertMintCapsBeaconSet();
    }

    function testAssertMintCapsBeaconSetRevertsOnOtherImplementation() external {
        address beacon = LibOrchestratorInvariants.mintCapsBeacon();
        address other = address(new ST0xOrchestrator());
        vm.prank(timelock);
        UpgradeableBeacon(beacon).upgradeTo(other);
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconImplementationMismatch.selector, beacon, LibProdDeployCurrent.ST0X_ORCHESTRATOR, other
            )
        );
        harness.callAssertMintCapsBeaconSet();
    }

    function testAssertMintCapsInstancePasses() external {
        deployInstance();
        harness.callAssertMintCapsInstance(SAFE);
    }

    /// @notice The Safe may hold `EMERGENCY_ROLE`: it is an operating role
    /// the timelock can grant it.
    function testAssertMintCapsInstanceAllowsSafeEmergencyRole() external {
        IAccessControl acl = deployInstance();
        vm.prank(timelock);
        acl.grantRole(ORCHESTRATOR_EMERGENCY_ROLE, SAFE);
        harness.callAssertMintCapsInstance(SAFE);
    }

    function testAssertMintCapsInstanceRevertsWhenMissing() external {
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorInstanceMissing.selector, LibOrchestratorInvariants.mintCapsInstance())
        );
        harness.callAssertMintCapsInstance(SAFE);
    }

    /// @notice The timelock losing any admin role fails, naming that role.
    function testFuzzAssertMintCapsInstanceRevertsWhenTimelockLacksAdminRole(uint256 index) external {
        IAccessControl acl = deployInstance();
        bytes32 role = adminRoles()[index % 4];
        vm.prank(timelock);
        acl.revokeRole(role, timelock);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorRoleMissing.selector, address(acl), role, timelock));
        harness.callAssertMintCapsInstance(SAFE);
    }

    /// @notice The Safe or the deploy key holding any admin role fails,
    /// naming that holder and role.
    function testFuzzAssertMintCapsInstanceRevertsOnOtherAdminHolder(uint256 index, bool safe) external {
        IAccessControl acl = deployInstance();
        bytes32 role = adminRoles()[index % 4];
        address holder = safe ? SAFE : deployKey;
        vm.prank(timelock);
        acl.grantRole(role, holder);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorUnexpectedRoleHolder.selector, address(acl), role, holder));
        harness.callAssertMintCapsInstance(SAFE);
    }

    /// @notice The timelock or the deploy key holding any operating role
    /// fails, naming that holder and role.
    function testFuzzAssertMintCapsInstanceRevertsOnOperatingRoleHolder(uint256 index, bool isTimelock) external {
        IAccessControl acl = deployInstance();
        bytes32 role = operatingRoles()[index % 3];
        address holder = isTimelock ? timelock : deployKey;
        vm.prank(timelock);
        acl.grantRole(role, holder);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorUnexpectedRoleHolder.selector, address(acl), role, holder));
        harness.callAssertMintCapsInstance(SAFE);
    }

    /// @notice The Safe holding `MINT_ROLE` or `BURN_ROLE` fails.
    function testFuzzAssertMintCapsInstanceRevertsOnSafeMintOrBurn(bool mint) external {
        IAccessControl acl = deployInstance();
        bytes32 role = operatingRoles()[mint ? 0 : 1];
        vm.prank(timelock);
        acl.grantRole(role, SAFE);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorUnexpectedRoleHolder.selector, address(acl), role, SAFE));
        harness.callAssertMintCapsInstance(SAFE);
    }

    /// @notice Every role's admin is pinned: rewiring any one of the seven to
    /// a different admin fails, naming the role, the expected admin and the
    /// actual one.
    function testFuzzAssertMintCapsInstanceRevertsOnRoleAdminRewired(uint256 index, bytes32 wrongAdmin) external {
        IAccessControl acl = deployInstance();
        bytes32[4] memory admins = adminRoles();
        bytes32[3] memory operating = operatingRoles();
        bytes32[7] memory roles = [admins[0], operating[0], admins[1], operating[1], admins[2], operating[2], admins[3]];
        bytes32[7] memory expected = [admins[0], admins[1], admins[1], admins[2], admins[2], admins[3], admins[3]];
        index = index % 7;
        vm.assume(wrongAdmin != expected[index]);
        setRoleAdmin(address(acl), roles[index], wrongAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorRoleAdminUnexpected.selector, address(acl), roles[index], expected[index], wrongAdmin
            )
        );
        harness.callAssertMintCapsInstance(SAFE);
    }
}
