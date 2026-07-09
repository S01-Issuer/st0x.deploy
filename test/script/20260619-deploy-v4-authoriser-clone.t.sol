// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {ERC1167_PREFIX, ERC1167_SUFFIX} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1167Proxy.sol";

import {ICloneableFactoryV2} from "rain-factory-0.1.1/src/interface/ICloneableFactoryV2.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {
    DeployV4AuthoriserClone,
    V4ImplNotDeployed,
    V4ImplCodehashMismatch,
    CloneFactoryNotDeployed,
    CloneFactoryCodehashMismatch,
    DeployerStillHoldsAdminRole,
    ExpectedGrantMissing,
    CloneCodehashMismatch
} from "../../script/20260619-deploy-v4-authoriser-clone.s.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {DeployV4AuthoriserCloneHarness} from "./DeployV4AuthoriserCloneHarness.sol";

/// @title DeployV4AuthoriserCloneTest
/// @notice Fork tests for the broadcast-driven V4 authoriser clone deploy.
///
/// Test setup runs each test against an unpinned Base head fork. The script
/// is invoked via `vm.prank(deployer, deployer)`, so `msg.sender` in `run()`
/// is the synthetic deployer address for the whole call. `vm.startBroadcast()`
/// inside the script no-ops under `forge test` — state changes still apply
/// against the fork snapshot, they just are not re-broadcast.
///
/// @dev The V4 impl has not yet been Zoltu-deployed on Base at the time this
/// script lands. Each test etches the V4 impl runtime bytecode at the pinned
/// address so the impl pre-flight passes; the runtime is captured from a
/// freshly-compiled `StoxOffchainAssetReceiptVaultAuthorizerV1`, whose
/// codehash matches the `LibProdDeployV4` pin by construction.
contract DeployV4AuthoriserCloneTest is Test {
    DeployV4AuthoriserClone internal script;
    DeployV4AuthoriserCloneHarness internal harness;
    address internal deployer;
    address internal safe;
    address internal v4Impl;
    bytes internal v4ImplRuntime;
    address internal cloneFactory;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new DeployV4AuthoriserClone();
        harness = new DeployV4AuthoriserCloneHarness();
        deployer = makeAddr("deployer");
        vm.deal(deployer, 100 ether);
        safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        cloneFactory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;

        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        v4ImplRuntime = address(impl).code;
        vm.etch(v4Impl, v4ImplRuntime);
    }

    /// @notice Happy path: replicate the deploy sequence with
    /// `vm.prank(deployer)` per external call, then run the same
    /// `_assertPostState` check `run()` would through the harness.
    /// Mirrors `MigrateBeaconOwnersTest.simulateTransfers` — the state
    /// change is driven inline because `vm.startBroadcast` (which the
    /// script wraps around the sequence) is mutually exclusive with
    /// `vm.prank` in `forge test`.
    function testHappyPathLeavesExpectedGrantsAndNoDeployerAdmin() external {
        selectBaseFork();

        // Step 1: deploy the clone under the deployer.
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: deployer}));
        vm.prank(deployer, deployer);
        address clone = ICloneableFactoryV2(cloneFactory).clone(v4Impl, initData);

        IAccessControl acl = IAccessControl(clone);
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        bytes32[7] memory adminRoles = _autoGrantedAdminRoles();

        // Step 2: mirror the six non-admin operational grants under
        // the deployer (who holds every `_ADMIN` role from init).
        for (uint256 i = 5; i < allGrants.length; i++) {
            vm.prank(deployer, deployer);
            acl.grantRole(allGrants[i].role, allGrants[i].grantee);
        }

        // Step 3: grant each of the SEVEN auto-granted `_ADMIN` roles
        // (five V3-era + two corporate-action admins) to the Safe.
        for (uint256 i = 0; i < adminRoles.length; i++) {
            vm.prank(deployer, deployer);
            acl.grantRole(adminRoles[i], safe);
        }

        // Step 4: renounce each `_ADMIN` role from the deployer.
        for (uint256 i = 0; i < adminRoles.length; i++) {
            vm.prank(deployer, deployer);
            acl.renounceRole(adminRoles[i], deployer);
        }

        // Post-state check via the harness — same code path the script's
        // `run()` executes after `vm.stopBroadcast()`.
        harness.callAssertPostState(clone, deployer, v4Impl);

        // Redundant fine-grained assertions so any regression surfaces
        // here rather than as a plain "assertPostState reverted".
        for (uint256 i = 0; i < allGrants.length; i++) {
            assertTrue(acl.hasRole(allGrants[i].role, allGrants[i].grantee), "expected grant missing on live clone");
        }
        for (uint256 i = 0; i < adminRoles.length; i++) {
            assertTrue(acl.hasRole(adminRoles[i], safe), "Safe missing an auto-granted admin role");
            assertFalse(acl.hasRole(adminRoles[i], deployer), "deployer retained an admin role");
        }
    }

    /// @notice The seven `_ADMIN` roles the base + ST0x-override
    /// `initialize` auto-grant. Mirrors the script's
    /// `autoGrantedAdminRoles()` (internal there, re-listed here).
    function _autoGrantedAdminRoles() internal pure returns (bytes32[7] memory roles) {
        roles[0] = keccak256("CERTIFY_ADMIN");
        roles[1] = keccak256("CONFISCATE_RECEIPT_ADMIN");
        roles[2] = keccak256("CONFISCATE_SHARES_ADMIN");
        roles[3] = keccak256("DEPOSIT_ADMIN");
        roles[4] = keccak256("WITHDRAW_ADMIN");
        roles[5] = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");
        roles[6] = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");
    }

    /// @notice Pre-flight rejects a missing V4 impl. `vm.etch` with empty
    /// bytes zeros the runtime code at the pin so `impl.code.length == 0`
    /// trips first.
    function testRunRejectsMissingV4Impl() external {
        selectBaseFork();
        vm.etch(v4Impl, "");
        vm.expectRevert(abi.encodeWithSelector(V4ImplNotDeployed.selector, v4Impl));
        vm.prank(deployer, deployer);
        script.run();
    }

    /// @notice Pre-flight rejects a V4 impl whose codehash drifts from the
    /// pinned value. Simulated by etching alien bytecode so `code.length > 0`
    /// but the codehash mismatches.
    function testRunRejectsV4ImplCodehashDrift() external {
        selectBaseFork();
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(v4Impl, bogusCode);
        bytes32 expected = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1;
        bytes32 actual = keccak256(bogusCode);
        vm.expectRevert(abi.encodeWithSelector(V4ImplCodehashMismatch.selector, v4Impl, expected, actual));
        vm.prank(deployer, deployer);
        script.run();
    }

    /// @notice Pre-flight rejects a missing CloneFactory. `vm.etch` with
    /// empty bytes at the factory pin address.
    function testRunRejectsMissingCloneFactory() external {
        selectBaseFork();
        vm.etch(cloneFactory, "");
        vm.expectRevert(abi.encodeWithSelector(CloneFactoryNotDeployed.selector, cloneFactory));
        vm.prank(deployer, deployer);
        script.run();
    }

    /// @notice Pre-flight rejects a CloneFactory whose codehash drifts from
    /// the rain-factory pin. Simulated by etching alien bytecode so
    /// `code.length > 0` but the codehash mismatches.
    function testRunRejectsCloneFactoryCodehashDrift() external {
        selectBaseFork();
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(cloneFactory, bogusCode);
        bytes32 expected = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH;
        bytes32 actual = keccak256(bogusCode);
        vm.expectRevert(abi.encodeWithSelector(CloneFactoryCodehashMismatch.selector, cloneFactory, expected, actual));
        vm.prank(deployer, deployer);
        script.run();
    }

    /// @notice Deploy + configure a clone under `deployer`, optionally
    /// perturbing exactly one step so a specific `_assertPostState`
    /// guard is the one that trips. With all skips disabled this
    /// produces the same correct clone the happy path builds.
    /// @param skipRenounce When true, step 4 is skipped so `deployer`
    /// retains every auto-granted admin role.
    /// @param skipMirrorIndex An `expectedGrants()` index (in
    /// `[MIRROR_START..]`) whose operational grant is skipped, or
    /// `type(uint256).max` to mirror all six.
    /// @param skipAdminIndex An `autoGrantedAdminRoles()` index whose
    /// grant-to-Safe is skipped, or `type(uint256).max` to grant all
    /// seven.
    /// @return clone The freshly-configured (possibly perturbed) clone.
    function _deployAndConfigure(bool skipRenounce, uint256 skipMirrorIndex, uint256 skipAdminIndex)
        internal
        returns (address clone)
    {
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: deployer}));
        vm.prank(deployer, deployer);
        clone = ICloneableFactoryV2(cloneFactory).clone(v4Impl, initData);

        IAccessControl acl = IAccessControl(clone);
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        bytes32[7] memory adminRoles = _autoGrantedAdminRoles();

        // Step 2: mirror the operational grants (indices 5..).
        for (uint256 i = 5; i < allGrants.length; i++) {
            if (i == skipMirrorIndex) continue;
            vm.prank(deployer, deployer);
            acl.grantRole(allGrants[i].role, allGrants[i].grantee);
        }

        // Step 3: grant each auto-granted admin role to the Safe.
        for (uint256 i = 0; i < adminRoles.length; i++) {
            if (i == skipAdminIndex) continue;
            vm.prank(deployer, deployer);
            acl.grantRole(adminRoles[i], safe);
        }

        // Step 4: renounce each auto-granted admin role from the deployer.
        if (!skipRenounce) {
            for (uint256 i = 0; i < adminRoles.length; i++) {
                vm.prank(deployer, deployer);
                acl.renounceRole(adminRoles[i], deployer);
            }
        }
    }

    /// @notice `_assertPostState` reverts `DeployerStillHoldsAdminRole`
    /// when step 4's renounce is skipped and the deployer keeps its
    /// auto-granted admin roles. Proves the de-privilege guard fires.
    function testAssertPostStateRejectsDeployerRetainingAdmin() external {
        selectBaseFork();
        address clone = _deployAndConfigure(true, type(uint256).max, type(uint256).max);
        bytes32 certifyAdmin = _autoGrantedAdminRoles()[0];
        vm.expectRevert(abi.encodeWithSelector(DeployerStillHoldsAdminRole.selector, certifyAdmin, deployer));
        harness.callAssertPostState(clone, deployer, v4Impl);
    }

    /// @notice `_assertPostState` reverts `ExpectedGrantMissing` when an
    /// operational grant from `expectedGrants()` is absent. Proves the
    /// expected-grants sweep fires.
    function testAssertPostStateRejectsMissingOperationalGrant() external {
        selectBaseFork();
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        uint256 skipped = 5;
        address clone = _deployAndConfigure(false, skipped, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(ExpectedGrantMissing.selector, allGrants[skipped].role, allGrants[skipped].grantee)
        );
        harness.callAssertPostState(clone, deployer, v4Impl);
    }

    /// @notice `_assertPostState` reverts `ExpectedGrantMissing` when the
    /// Safe is missing an auto-granted admin role. Skips a corporate-
    /// action admin specifically — those two are NOT in `expectedGrants()`,
    /// so only the dedicated "Safe holds every admin role" sweep can catch
    /// this. Proves that sweep fires.
    function testAssertPostStateRejectsSafeMissingAdminRole() external {
        selectBaseFork();
        bytes32[7] memory adminRoles = _autoGrantedAdminRoles();
        // Index 5 = SCHEDULE_CORPORATE_ACTION_ADMIN (V4-override only).
        uint256 skippedAdmin = 5;
        address clone = _deployAndConfigure(false, type(uint256).max, skippedAdmin);
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, adminRoles[skippedAdmin], safe));
        harness.callAssertPostState(clone, deployer, v4Impl);
    }

    /// @notice `_assertPostState` reverts `CloneCodehashMismatch` when the
    /// clone is an EIP-1167 proxy of an impl OTHER than the pinned V4 impl.
    /// Proves the codehash guard fires — the check that whatever lands at
    /// the clone address is exactly the audited V4 impl's proxy.
    function testAssertPostStateRejectsNonMatchingCloneCodehash() external {
        selectBaseFork();
        // A second address carrying the same runtime but at a different
        // location; a clone of it embeds that address, so its EIP-1167
        // codehash differs from the one derived from the pinned V4 impl.
        address wrongImpl = makeAddr("wrongImpl");
        vm.etch(wrongImpl, v4ImplRuntime);
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: deployer}));
        vm.prank(deployer, deployer);
        address badClone = ICloneableFactoryV2(cloneFactory).clone(wrongImpl, initData);

        bytes32 expected = keccak256(abi.encodePacked(ERC1167_PREFIX, v4Impl, ERC1167_SUFFIX));
        bytes32 actual = badClone.codehash;
        assertTrue(actual != expected, "test setup: wrong-impl clone codehash unexpectedly matched");

        vm.expectRevert(abi.encodeWithSelector(CloneCodehashMismatch.selector, badClone, expected, actual));
        harness.callAssertPostState(badClone, deployer, v4Impl);
    }

    /// @notice The impl's `initialize` auto-grants EXACTLY the seven
    /// `_ADMIN` roles the script's `autoGrantedAdminRoles()` hand-list
    /// enumerates to `initialAdmin`, and — critically — does NOT grant
    /// `DEFAULT_ADMIN_ROLE`. If the impl granted an admin role outside the
    /// hand-list (or the OZ root), the script's step-3 transfer + step-4
    /// renounce would silently miss it and the deployer would keep
    /// privilege the post-state check never inspects. Pins the hand-list
    /// to the real impl rather than to itself.
    function testInitAutoGrantsExactlyTheSevenAdminRolesToInitialAdmin() external {
        selectBaseFork();
        address initialAdmin = makeAddr("someInitialAdmin");
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: initialAdmin}));
        vm.prank(deployer, deployer);
        address clone = ICloneableFactoryV2(cloneFactory).clone(v4Impl, initData);

        IAccessControl acl = IAccessControl(clone);
        bytes32[7] memory adminRoles = _autoGrantedAdminRoles();
        for (uint256 i = 0; i < adminRoles.length; i++) {
            assertTrue(acl.hasRole(adminRoles[i], initialAdmin), "impl did not auto-grant an expected admin role");
        }
        // `bytes32(0)` is OZ's DEFAULT_ADMIN_ROLE — the root that admins
        // every other role. `initialAdmin` must NOT hold it, else the
        // seven-role renounce leaves the deployer with root regardless.
        assertFalse(acl.hasRole(bytes32(0), initialAdmin), "initialAdmin unexpectedly holds DEFAULT_ADMIN_ROLE");
    }

    /// @notice The script's own slice constants and admin-role list agree
    /// with (a) the invariant map length and (b) the replica list the
    /// happy path drives the sequence with — so a drift in either the
    /// script's constants or the invariant map is caught here rather than
    /// silently diverging from the hand-replicated happy path.
    function testScriptConstantsMatchInvariantMapAndReplica() external {
        selectBaseFork();
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        assertEq(harness.mirrorStartIndex(), 5, "MIRROR_START_INDEX drifted from the happy-path replica");
        assertEq(harness.mirrorCount(), 6, "MIRROR_COUNT drifted from the happy-path replica");
        assertEq(
            harness.mirrorStartIndex() + harness.mirrorCount(),
            allGrants.length,
            "slice constants do not cover the invariant map exactly"
        );
        bytes32[7] memory scriptRoles = harness.autoGrantedAdminRolesExternal();
        bytes32[7] memory replicaRoles = _autoGrantedAdminRoles();
        for (uint256 i = 0; i < scriptRoles.length; i++) {
            assertEq(scriptRoles[i], replicaRoles[i], "script admin-role list drifted from the test replica");
        }
        // The live invariant map satisfies the script's own slice guard.
        harness.callAssertGrantsSliceInvariant();
    }
}
