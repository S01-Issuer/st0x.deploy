// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";

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
    ExpectedGrantMissing
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
        v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
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

        // Step 2: mirror the six non-admin operational grants under
        // the deployer (who holds every `_ADMIN` role from init).
        for (uint256 i = 5; i < allGrants.length; i++) {
            vm.prank(deployer, deployer);
            acl.grantRole(allGrants[i].role, allGrants[i].grantee);
        }

        // Step 3: grant each `_ADMIN` role to the Safe.
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(deployer, deployer);
            acl.grantRole(allGrants[i].role, safe);
        }

        // Step 4: renounce each `_ADMIN` role from the deployer.
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(deployer, deployer);
            acl.renounceRole(allGrants[i].role, deployer);
        }

        // Post-state check via the harness — same code path the script's
        // `run()` executes after `vm.stopBroadcast()`.
        harness.callAssertPostState(clone, deployer, v4Impl);

        // Redundant fine-grained assertions so any regression surfaces
        // here rather than as a plain "assertPostState reverted".
        for (uint256 i = 0; i < allGrants.length; i++) {
            assertTrue(acl.hasRole(allGrants[i].role, allGrants[i].grantee), "expected grant missing on live clone");
        }
        for (uint256 i = 0; i < 5; i++) {
            assertFalse(acl.hasRole(allGrants[i].role, deployer), "deployer retained an admin role");
        }
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
        bytes32 expected = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6;
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
}
