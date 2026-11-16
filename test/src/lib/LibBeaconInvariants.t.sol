// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibBeaconInvariants,
    IOwnable,
    BeaconCodehashMismatch,
    BeaconNotDeployed,
    BeaconOwnerMismatch,
    BeaconImplementationMismatch,
    CreateNonceOutOfRange,
    UnsupportedChainForProdBeacons
} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibProdBeaconsBase} from "../../../src/lib/LibProdBeaconsBase.sol";
import {LibProdBeacons0_1_1} from "../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibBeaconInvariantsHarness} from "./LibBeaconInvariantsHarness.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// The frozen 0.1.30 orchestrator beacon-set deployer's beacon getter.
interface IOrchestratorBeaconSet0_1_30 {
    function iOrchestratorBeacon() external view returns (IBeacon);
}

/// @title LibBeaconInvariantsTest
/// @notice Inverted tests that exercise each invariant in
/// `LibBeaconInvariants` by injecting drift via `vm.etch` / `vm.mockCall`
/// into Base's production beacons built locally and asserting the matching
/// typed error is raised, and the pass paths against each chain's.
contract LibBeaconInvariantsTest is Test {
    LibBeaconInvariantsHarness internal harness;

    /// @notice Base's production beacons built locally, with the active chain
    /// id set to Base.
    function selectLocalBase() internal {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        LibLocalProdState.beacons(vm, LibSafeInvariants.BASE_CHAIN_ID);
        harness = new LibBeaconInvariantsHarness();
    }

    /// @notice `assertBeaconInvariants` trips `BeaconCodehashMismatch` when
    /// the beacon's runtime codehash drifts from the pinned OZ
    /// `UpgradeableBeacon` bytecode. Simulated by `vm.etch`-ing a single
    /// `INVALID` opcode at the beacon address; `extcodehash` then returns the
    /// hash of `0xFE`, which differs from the pinned codehash. Uses Base's
    /// receipt vault beacon as the victim.
    function testInvertedBeaconCodehashMismatch() external {
        selectLocalBase();
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        bytes memory mutatedCode = hex"FE";
        vm.etch(beacon, mutatedCode);
        bytes32 mutatedCodehash;
        assembly ("memory-safe") {
            mutatedCodehash := extcodehash(beacon)
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconCodehashMismatch.selector,
                beacon,
                LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH,
                mutatedCodehash
            )
        );
        harness.callAssertBeaconInvariants(
            beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @notice `assertBeaconInvariants` trips `BeaconOwnerMismatch` when the
    /// beacon's `owner()` differs from the expected owner. Simulated by
    /// mocking `owner()` on Base's receipt vault beacon to a rogue address.
    function testInvertedBeaconOwnerMismatch() external {
        selectLocalBase();
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address rogueOwner = address(0xBADC0DE);
        vm.mockCall(beacon, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector, beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, rogueOwner
            )
        );
        harness.callAssertBeaconInvariants(
            beacon, LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @notice `assertBeaconInvariants` trips `BeaconImplementationMismatch`
    /// when the beacon's `implementation()` differs from the expected
    /// implementation. Simulated by mocking `implementation()` on Base's
    /// receipt vault beacon to a rogue address. The expected owner is the
    /// governance timelock, the beacon's owner, so the owner check passes and
    /// the revert is specifically the implementation gate.
    function testInvertedBeaconImplementationMismatch() external {
        selectLocalBase();
        address beacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address rogueImpl = address(0xBADBEEF);
        vm.mockCall(beacon, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(rogueImpl));
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconImplementationMismatch.selector,
                beacon,
                LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
                rogueImpl
            )
        );
        harness.callAssertBeaconInvariants(
            beacon, LibBeaconInvariants.PROD_BEACON_OWNER, LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION
        );
    }

    /// @notice `UPGRADEABLE_BEACON_CODEHASH` is a re-declaration of
    /// `LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1` (kept local so
    /// the beacon invariant does not reach into the V1 deploy lib). Pin the
    /// equality structurally: without this the two copies are tied only
    /// transitively, through separate suites asserting each against the same
    /// beacons, and a drifted copy would surface as an on-chain
    /// "mismatch" instead of the source defect it is.
    function testUpgradeableBeaconCodehashMatchesV1DeployPin() external pure {
        assertEq(LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH, LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1);
    }

    /// @notice Base's IN-USE beacons are the V1-generation addresses. The
    /// later 0.1.1-address beacons exist on Base but production never adopted
    /// them, so returning those would assert ownership of a deploy artifact
    /// nothing runs on while leaving the live beacons unpinned.
    function testProdBeaconsForChainIdBaseIsTheV1Generation() external {
        harness = new LibBeaconInvariantsHarness();
        address[4] memory beacons = harness.callProdBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(beacons[0], LibProdDeployV1.STOX_RECEIPT_BEACON_V1, "receipt beacon");
        assertEq(beacons[1], LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, "receipt vault beacon");
        assertEq(beacons[2], LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1, "wrapped vault beacon");
    }

    /// @notice Ethereum bootstrapped at 0.1.1, so its in-use beacons are that
    /// generation — the two read live from the 0.1.1 beacon-set deployer plus
    /// the wrapped beacon's own pin. Pinned against the source lib so the
    /// chain-id dispatch cannot silently answer with Base's set.
    function testProdBeaconsForChainIdEthereumIsThe011Set() external {
        LibLocalProdState.beacons(vm, LibSafeInvariants.ETHEREUM_CHAIN_ID);
        harness = new LibBeaconInvariantsHarness();
        address[4] memory beacons = harness.callProdBeaconsForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        address[4] memory expected = LibProdBeacons0_1_1.beacons();
        assertEq(beacons[0], expected[0], "receipt beacon");
        assertEq(beacons[1], expected[1], "receipt vault beacon");
        assertEq(beacons[2], expected[2], "wrapped vault beacon");
        assertTrue(beacons[0] != LibProdDeployV1.STOX_RECEIPT_BEACON_V1, "answered with Base's set");
    }

    /// @notice A chain with no pinned in-use set reverts rather than falling
    /// back to another chain's beacons. A fallback would assert ownership of
    /// contracts that do not exist on the active chain, and `code.length == 0`
    /// would report that as a missing beacon rather than as an unsupported
    /// chain.
    function testProdBeaconsForChainIdRevertsForUnpinnedChain() external {
        harness = new LibBeaconInvariantsHarness();
        uint256 arbitrum = 42161;
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForProdBeacons.selector, arbitrum));
        harness.callProdBeaconsForChainId(arbitrum);
    }

    /// @notice `assertProdBeaconsOwnedByChainTimelock` trips `BeaconOwnerMismatch`
    /// when an in-use beacon is held by anything other than the active chain's
    /// governance timelock. Whoever owns an in-use beacon can repoint every
    /// production vault proxy on the chain, so the rogue owner here stands in
    /// for the whole class of compromise this assert exists to catch.
    function testInvertedProdBeaconOwnerMismatch() external {
        selectLocalBase();
        address beacon = LibProdBeaconsBase.beacons()[1];
        address rogueOwner = address(0xBADC0DE);
        vm.mockCall(beacon, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID),
                rogueOwner
            )
        );
        harness.callAssertProdBeaconsOwnedByChainTimelock(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @notice An in-use beacon with no code trips `BeaconNotDeployed` rather
    /// than reaching `owner()`. A staticcall to a codeless address succeeds
    /// returning nothing, so without this guard the failure would surface as a
    /// decode revert that names neither the beacon nor the reason.
    function testInvertedProdBeaconNotDeployed() external {
        selectLocalBase();
        address beacon = LibProdBeaconsBase.beacons()[0];
        vm.etch(beacon, "");
        vm.expectRevert(abi.encodeWithSelector(BeaconNotDeployed.selector, beacon));
        harness.callAssertProdBeaconsOwnedByChainTimelock(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @notice An in-use beacon whose runtime code drifts from the pinned OZ
    /// `UpgradeableBeacon` bytecode trips `BeaconCodehashMismatch` BEFORE its
    /// `owner()` is read: the look-alike here mocks `owner()` to the expected
    /// timelock, so only the codehash pin stands between it and a pass. Without
    /// the pin, a swapped beacon shadowing `owner()` satisfies the ownership
    /// sweep while serving arbitrary `upgradeTo` semantics.
    function testInvertedProdBeaconCodehashMismatch() external {
        selectLocalBase();
        address beacon = LibProdBeaconsBase.beacons()[1];
        vm.etch(beacon, hex"FE");
        bytes32 mutatedCodehash;
        assembly ("memory-safe") {
            mutatedCodehash := extcodehash(beacon)
        }
        vm.mockCall(
            beacon,
            abi.encodeWithSelector(IOwnable.owner.selector),
            abi.encode(LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconCodehashMismatch.selector,
                beacon,
                LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH,
                mutatedCodehash
            )
        );
        harness.callAssertProdBeaconsOwnedByChainTimelock(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @notice `UPGRADEABLE_BEACON_CODEHASH_0_1_30` is the runtime of the beacon
    /// the frozen 0.1.30 orchestrator beacon-set deployer builds, re-derived
    /// from its creation code rather than transcribed.
    /// @dev The defect this exists to stop: the V1 pin was documented as "a
    /// property of the OZ bytecode rather than of any one deployment
    /// generation" and reused for the orchestrator beacon, which OZ 5.6.1 at
    /// `optimizer_runs = 2000` builds 130 bytes shorter. Nothing compared the
    /// two, so `MigrateOrchestratorBeaconOwner.run()` reverted
    /// `BeaconCodehashMismatch` in pre-flight on every chain while the suite
    /// stayed green. Deriving it from the frozen deployer keeps it tied to
    /// the live beacon's bytecode, which no later OZ bump or optimizer change
    /// moves.
    function testOrchestratorBeaconCodehashPin() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_0_1_30);
        address deployer =
            LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30);
        assertEq(
            address(IOrchestratorBeaconSet0_1_30(deployer).iOrchestratorBeacon()).codehash,
            LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH_0_1_30,
            "0.1.30 beacon pin no longer matches the beacon the frozen 0.1.30 deployer builds"
        );
    }

    /// @notice The two generation pins are distinct, and the V1 pin cannot be
    /// used for a beacon this tree builds.
    /// @dev Guards the shortcut of "fixing" a mismatch by repointing the V1
    /// constant, which the live V1 fleet is still asserted against.
    function testBeaconCodehashPinsAreDistinct() external pure {
        assertTrue(
            LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH != LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH_0_1_30,
            "generation pins collapsed into one value"
        );
    }

    /// @notice On every chain the four in-use beacons at their pinned
    /// codehashes, owned by the chain's timelock, pass.
    function testAssertProdBeaconsOwnedByChainTimelockOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.beacons(vm, chainIds[i]);
            LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock(chainIds[i]);
            vm.revertToState(snapshot);
        }
    }

    /// @notice On every chain each token beacon passes the V1-generation
    /// beacon assertion with the chain's timelock and its expected
    /// implementation.
    function testAssertBeaconInvariantsHoldsForEveryTokenBeacon() external {
        uint256[3] memory tokenBeacons = [
            LibBeaconInvariants.RECEIPT_BEACON_INDEX,
            LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX,
            LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX
        ];
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.beacons(vm, chainIds[i]);
            address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(chainIds[i]);
            address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(chainIds[i]);
            for (uint256 j = 0; j < tokenBeacons.length; j++) {
                LibBeaconInvariants.assertBeaconInvariants(
                    beacons[tokenBeacons[j]],
                    LibTimelockInvariants.timelockForChainId(chainIds[i]),
                    impls[tokenBeacons[j]]
                );
            }
            vm.revertToState(snapshot);
        }
    }

    function testFuzzCreateAddressIsTheCreateAtThatNonce(address deployer, uint8 nonce) external pure {
        nonce = uint8(bound(nonce, 1, 0x7f));
        assertEq(LibBeaconInvariants.createAddress(deployer, nonce), vm.computeCreateAddress(deployer, nonce));
    }

    function testFuzzCreateAddressRevertsAtNonceZero(address deployer) external {
        LibBeaconInvariantsHarness nonceHarness = new LibBeaconInvariantsHarness();
        vm.expectRevert(abi.encodeWithSelector(CreateNonceOutOfRange.selector, uint8(0)));
        nonceHarness.callCreateAddress(deployer, 0);
    }

    function testFuzzCreateAddressRevertsAboveTheSingleByteRange(address deployer, uint8 nonce) external {
        LibBeaconInvariantsHarness nonceHarness = new LibBeaconInvariantsHarness();
        nonce = uint8(bound(nonce, 0x80, type(uint8).max));
        vm.expectRevert(abi.encodeWithSelector(CreateNonceOutOfRange.selector, nonce));
        nonceHarness.callCreateAddress(deployer, nonce);
    }

    /// @notice The derived set is the set the chain resolves: off Base the
    /// receipt and receipt-vault beacons are the ones the real set deployer's
    /// constructor created; on Base it is the pinned set.
    function testDerivedBeaconsAreTheResolvedBeaconsOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.beacons(vm, chainIds[i]);
            address[4] memory derived = LibBeaconInvariants.prodDerivedBeaconsForChainId(chainIds[i]);
            address[4] memory resolved = LibBeaconInvariants.prodBeaconsForChainId(chainIds[i]);
            for (uint256 j = 0; j < resolved.length; j++) {
                assertEq(derived[j], resolved[j]);
            }
            vm.revertToState(snapshot);
        }
    }
}
