// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    ST0xOrchestrator,
    ORCHESTRATOR_MINT_ROLE,
    ORCHESTRATOR_MINT_ADMIN_ROLE,
    ORCHESTRATOR_BURN_ROLE,
    ORCHESTRATOR_BURN_ADMIN_ROLE,
    ORCHESTRATOR_EMERGENCY_ROLE,
    ORCHESTRATOR_EMERGENCY_ADMIN_ROLE
} from "../../../src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {
    BeaconNotDeployed,
    BeaconCodehashMismatch,
    BeaconOwnerMismatch,
    BeaconImplementationMismatch
} from "../../../src/lib/LibBeaconInvariants.sol";
import {
    LibOrchestratorInvariants,
    OrchestratorInstanceMissing,
    OrchestratorRoleMissing,
    OrchestratorRoleAdminUnexpected
} from "../../../src/lib/LibOrchestratorInvariants.sol";
import {LibOrchestratorInvariantsHarness} from "./LibOrchestratorInvariantsHarness.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "../../lib/LibTestOrchestratorDeploy.sol";

/// @title LibOrchestratorInvariantsMintCapsTest
/// @notice The mint-caps orchestrator invariants against a local deploy that
/// matches production: the current-release orchestrator and its beacon
/// Zoltu-deployed, then the instance the production deploy step creates, the
/// governance timelock bound as beacon initial owner and initial admin. Green
/// on that deploy, and each expected-grant, wiring or address deviation
/// reverts with its own typed error.
contract LibOrchestratorInvariantsMintCapsTest is Test {
    /// @notice OZ `AccessControlUpgradeable`'s ERC-7201 storage slot.
    bytes32 internal constant ACCESS_CONTROL_SLOT =
        keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessControl")) - 1)) & ~bytes32(uint256(0xff));

    LibOrchestratorInvariantsHarness internal harness;
    address internal timelock;
    address internal deployKey;
    address internal deployedBeacon;

    function setUp() external {
        harness = new LibOrchestratorInvariantsHarness();
        timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        LibTestDeploy.bindBeaconInitialOwner(vm, timelock);
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, timelock);
        deployKey = LibProdDeployCurrent.BEACON_INITIAL_OWNER;

        LibRainDeploy.etchZoltuFactory(vm);
        deployedBeacon = LibTestOrchestratorDeploy.deployBeacon();
    }

    function deployInstance() internal returns (IAccessControl) {
        return IAccessControl(LibTestOrchestratorDeploy.deployInstance(vm, deployKey));
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
    /// deploy actually creates them.
    function testMintCapsAddressesMatchDeploy() external {
        assertEq(deployedBeacon, LibOrchestratorInvariants.mintCapsBeacon(), "beacon");
        assertEq(address(deployInstance()), LibOrchestratorInvariants.mintCapsInstance(), "instance");
    }

    function testAssertMintCapsBeaconSetPasses() external view {
        harness.callAssertMintCapsBeaconSet();
    }

    function testAssertMintCapsBeaconSetRevertsWhenBeaconMissing() external {
        vm.etch(deployedBeacon, "");
        vm.expectRevert(abi.encodeWithSelector(BeaconNotDeployed.selector, deployedBeacon));
        harness.callAssertMintCapsBeaconSet();
    }

    function testFuzzAssertMintCapsBeaconSetRevertsOnOtherCode(bytes memory code) external {
        // Deployed code never starts 0xef (EIP-3541); vm.etch reads 0xef01 as an EIP-7702 designator.
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_CODEHASH);
        vm.etch(deployedBeacon, code);
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconCodehashMismatch.selector,
                deployedBeacon,
                LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_CODEHASH,
                keccak256(code)
            )
        );
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

    function testAssertMintCapsBeaconSetRevertsOnRenouncedOwner() external {
        address beacon = LibOrchestratorInvariants.mintCapsBeacon();
        vm.prank(timelock);
        UpgradeableBeacon(beacon).renounceOwnership();
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerMismatch.selector, beacon, timelock, address(0)));
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
        harness.callAssertMintCapsInstance();
    }

    /// @notice Expected-only: a grant beyond the expected pairs, of any role to
    /// any account, does not fail.
    function testFuzzAssertMintCapsInstanceIgnoresUnexpectedHolders(uint256 index, address holder) external {
        IAccessControl acl = deployInstance();
        bytes32[4] memory admins = adminRoles();
        bytes32[3] memory operating = operatingRoles();
        bytes32[7] memory roles = [admins[0], admins[1], admins[2], admins[3], operating[0], operating[1], operating[2]];
        vm.prank(timelock);
        acl.grantRole(roles[index % 7], holder);
        harness.callAssertMintCapsInstance();
    }

    function testAssertMintCapsInstanceRevertsWhenMissing() external {
        vm.expectRevert(
            abi.encodeWithSelector(OrchestratorInstanceMissing.selector, LibOrchestratorInvariants.mintCapsInstance())
        );
        harness.callAssertMintCapsInstance();
    }

    /// @notice The timelock losing any admin role fails, naming that role.
    function testFuzzAssertMintCapsInstanceRevertsWhenTimelockLacksAdminRole(uint256 index) external {
        IAccessControl acl = deployInstance();
        bytes32 role = adminRoles()[index % 4];
        vm.prank(timelock);
        acl.revokeRole(role, timelock);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorRoleMissing.selector, address(acl), role, timelock));
        harness.callAssertMintCapsInstance();
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
        harness.callAssertMintCapsInstance();
    }
}
