// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

import {
    ClosureNotDeployed,
    ClosureCodehashMismatch,
    OrchestratorAlreadyDeployed,
    UnexpectedSetDeployerNonce,
    InstanceAddressMismatch,
    DeployKeyHoldsAdmin
} from "../../script/20260818-deploy-orchestrator.s.sol";
import {DeployOrchestratorHarness} from "./DeployOrchestratorHarness.sol";
import {MigrationStateDrift} from "../../src/lib/LibMigrationInvariant.sol";
import {
    LibOrchestratorInvariants,
    ST0xOrchestratorBeaconSetDeployerLike,
    OrchestratorAdminMissing
} from "../../src/lib/LibOrchestratorInvariants.sol";
import {IST0xOrchestratorV1} from "../../src/interface/IST0xOrchestratorV1.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";

/// @title DeployOrchestratorTest
/// @notice Guard coverage for `20260818-deploy-orchestrator` without a fork:
/// each pre-flight refusal and each `assertDeployLanded` failure mode is
/// shown to fire. The live-fork walk of the rollout states is in
/// `20260818-deploy-orchestrator.prod.t.sol`.
contract DeployOrchestratorTest is Test {
    DeployOrchestratorHarness internal harness;

    address internal constant SAFE = address(0x5AFE);
    address internal constant DEPLOY_KEY = address(0xDEAD);

    function setUp() external {
        harness = new DeployOrchestratorHarness();
    }

    /// @notice Etch every closure contract's frozen 0.1.30 runtime bytecode
    /// at its pin, so the codehash pre-flight passes on a blank chain.
    function etchClosure() internal {
        vm.etch(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_30
        );
        vm.etch(LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_RUNTIME_CODE_0_1_30);
        vm.etch(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_30);
        vm.etch(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_30
        );
        vm.etch(LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30, LibProdDeployV4.ST0X_ORCHESTRATOR_RUNTIME_CODE_0_1_30);
        vm.etch(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_30
        );
    }

    /// @notice Mock the pinned beacon set so `assertBeaconSet` passes: the
    /// set deployer reports the pinned beacon, and the beacon reports the
    /// 0.1.30 implementation under the pinned owner.
    function mockBeaconSet() internal {
        vm.mockCall(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30,
            abi.encodeCall(ST0xOrchestratorBeaconSetDeployerLike.iOrchestratorBeacon, ()),
            abi.encode(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON)
        );
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON,
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30)
        );
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON,
            abi.encodeCall(Ownable.owner, ()),
            abi.encode(LibProdDeployV4.BEACON_INITIAL_OWNER)
        );
        vm.etch(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, hex"fe");
    }

    /// @notice Mock the pinned instance in the fully landed state: code
    /// present, Safe holding admin, deploy key holding nothing, vault-logic
    /// lock passing.
    function mockLandedInstance() internal {
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.etch(instance, hex"fe");
        vm.mockCall(instance, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(true));
        vm.mockCall(instance, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), DEPLOY_KEY)), abi.encode(false));
        vm.mockCall(instance, abi.encodeCall(IST0xOrchestratorV1.vaultLogicIsExpected, ()), abi.encode(true));
    }

    /// Closure pre-flight refuses a blank chain, naming the first missing
    /// contract (the corporate-actions facet, first in dependency order).
    function testClosureRefusesABlankChain() external {
        vm.expectRevert(
            abi.encodeWithSelector(ClosureNotDeployed.selector, LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30)
        );
        harness.assertClosureReady();
    }

    /// Closure pre-flight checks every contract: with all but the last
    /// etched, the refusal names the orchestrator beacon-set deployer.
    function testClosureChecksEveryContract() external {
        etchClosure();
        vm.etch(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureNotDeployed.selector, LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30
            )
        );
        harness.assertClosureReady();
    }

    /// Closure pre-flight refuses wrong bytecode at a pin — code presence is
    /// not enough, the codehash must be the audited 0.1.30 one.
    function testClosureRefusesWrongBytecode() external {
        etchClosure();
        vm.etch(LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30, hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureCodehashMismatch.selector,
                LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30,
                LibProdDeployV4.ST0X_ORCHESTRATOR_CODEHASH_0_1_30,
                keccak256(hex"fe")
            )
        );
        harness.assertClosureReady();
    }

    /// Closure pre-flight passes with the frozen 0.1.30 runtime at every pin.
    function testClosureAcceptsTheFrozenBytecode() external {
        etchClosure();
        harness.assertClosureReady();
    }

    /// A live pinned instance refuses the deploy — re-dispatch cannot mint a
    /// duplicate.
    function testRefusesWhenInstanceAlreadyDeployed() external {
        vm.etch(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorAlreadyDeployed.selector, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE
            )
        );
        harness.assertNoInstanceYet(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30);
    }

    /// A set deployer whose nonce shows an earlier `deploy()` (without code
    /// at the pin) is unknown drift, not a deploy target.
    function testRefusesUnexpectedSetDeployerNonce() external {
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        vm.etch(setDeployer, hex"fe");
        vm.setNonce(setDeployer, 3);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedSetDeployerNonce.selector, setDeployer, 3));
        harness.assertNoInstanceYet(setDeployer);
    }

    /// The fresh-deploy state — no instance code, deployer nonce 2 — passes.
    function testAcceptsTheFreshDeployState() external {
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        vm.etch(setDeployer, hex"fe");
        vm.setNonce(setDeployer, 2);
        harness.assertNoInstanceYet(setDeployer);
    }

    /// `assertDeployLanded` refuses an instance address other than the pin —
    /// a `deploy()` return value the nonce-2 derivation disagrees with.
    function testLandedRefusesAnUnpinnedInstance() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                InstanceAddressMismatch.selector, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, address(0xBAD)
            )
        );
        harness.assertDeployLanded(address(0xBAD), SAFE, DEPLOY_KEY);
    }

    /// `assertDeployLanded` refuses an instance whose admin is not the Safe.
    function testLandedRefusesWhenSafeLacksAdmin() external {
        mockBeaconSet();
        mockLandedInstance();
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.mockCall(instance, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), SAFE)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAdminMissing.selector, instance, SAFE));
        harness.assertDeployLanded(instance, SAFE, DEPLOY_KEY);
    }

    /// `assertDeployLanded` refuses an instance still holding admin for the
    /// deploy key.
    function testLandedRefusesWhenDeployKeyHoldsAdmin() external {
        mockBeaconSet();
        mockLandedInstance();
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        vm.mockCall(instance, abi.encodeCall(IAccessControl.hasRole, (bytes32(0), DEPLOY_KEY)), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(DeployKeyHoldsAdmin.selector, instance, DEPLOY_KEY));
        harness.assertDeployLanded(instance, SAFE, DEPLOY_KEY);
    }

    /// The beacon pin is the beacon-set deployer's `CREATE` at account nonce
    /// 1 (its constructor's `new UpgradeableBeacon`). Re-derived here so a
    /// drifted `BuildPointers` literal fails a test — the beacon analogue of
    /// `testAuthoriserV4ClonePin`.
    function testOrchestratorBeaconPin() external pure {
        assertEq(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON,
            vm.computeCreateAddress(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30, 1),
            "beacon pin drifted from the deployer nonce-1 CREATE derivation"
        );
    }

    /// The instance pin is the beacon-set deployer's `CREATE` at account
    /// nonce 2 (the first `deploy()` call's `BeaconProxy`). Re-derived here
    /// so a drifted `BuildPointers` literal fails a test.
    function testOrchestratorInstancePin() external pure {
        assertEq(
            LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE,
            vm.computeCreateAddress(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30, 2),
            "instance pin drifted from the deployer nonce-2 CREATE derivation"
        );
    }

    /// `assertDeployLanded` passes the fully landed state.
    function testLandedAcceptsTheLandedState() external {
        mockBeaconSet();
        mockLandedInstance();
        harness.assertDeployLanded(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, SAFE, DEPLOY_KEY);
    }

    /// The beacon-owner invariant accepts the post-migration state too: a
    /// beacon already owned by the Safe (after
    /// `20260818-migrate-orchestrator-beacon-owner`) passes.
    function testLandedAcceptsASafeOwnedBeacon() external {
        mockBeaconSet();
        mockLandedInstance();
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON, abi.encodeCall(Ownable.owner, ()), abi.encode(SAFE)
        );
        harness.assertDeployLanded(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, SAFE, DEPLOY_KEY);
    }

    /// A beacon owner that is neither the deploy EOA nor the Safe is
    /// migration-state drift, before or after the deadline.
    function testLandedRefusesADriftedBeaconOwner() external {
        mockBeaconSet();
        mockLandedInstance();
        vm.mockCall(
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON,
            abi.encodeCall(Ownable.owner, ()),
            abi.encode(address(0xBAD))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationStateDrift.selector,
                "ST0X_ORCHESTRATOR_BEACON.owner()",
                bytes32(uint256(uint160(LibProdDeployV4.BEACON_INITIAL_OWNER))),
                bytes32(uint256(uint160(SAFE))),
                bytes32(uint256(uint160(address(0xBAD))))
            )
        );
        harness.assertDeployLanded(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, SAFE, DEPLOY_KEY);
    }
}
