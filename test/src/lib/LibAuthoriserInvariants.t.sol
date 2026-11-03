// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {
    LibAuthoriserInvariants,
    RoleGrant,
    AuthoriserNotReady,
    UnsupportedChainForAuthoriser,
    ExpectedGrantMissing,
    AuthoriserImplCodehashMismatch
} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_0_1_1} from "rain-factory-deploy-0.2.5/src/generated/0_1_1/CloneFactory.sol";

/// @title LibAuthoriserInvariantsTest
/// @notice The authoriser pins, the chain-to-clone tables, the expected-grant
/// maps, and each `LibAuthoriserInvariants` assertion tripped by a mocked or
/// etched drift.
contract LibAuthoriserInvariantsTest is Test {
    /// @notice The four factory-derived clone pins are the first CREATE from
    /// the canonical CloneFactory (nonce 1) on each chain, re-derived here so a
    /// mistyped literal fails fork-free. Base's clone came from a factory with
    /// history and is not derivable.
    function testClonePinsMatchTheFactoryNonceOneDerivation() external pure {
        address derived = vm.computeCreateAddress(CLONE_FACTORY_0_1_1, 1);
        assertEq(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM, derived, "ethereum");
        assertEq(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM, derived, "hyperevm");
        assertEq(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD, derived, "robinhood");
        assertEq(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC, derived, "bsc");
        assertNotEq(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE, derived, "base");
    }

    /// @notice The one chain-to-clone table resolves every pinned chain to
    /// its slot and refuses the rest, fork-free.
    function testAuthoriserForChainIdResolvesEveryPinnedChain() external {
        assertEq(
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.BASE_CHAIN_ID),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            "base"
        );
        assertEq(
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            "ethereum"
        );
        assertEq(
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.HYPEREVM_CHAIN_ID),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM,
            "hyperevm"
        );
        assertEq(
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ROBINHOOD_CHAIN_ID),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD,
            "robinhood"
        );
        assertEq(
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.BSC_CHAIN_ID),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC,
            "bsc"
        );
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForAuthoriser.selector, uint256(123456)));
        harness.callAuthoriserForChainId(123456);
    }

    /// @notice A governed chain whose pin has no code here (no fork) is
    /// refused as not ready rather than returned; the pin alone is not
    /// enough.
    function testActiveChainAuthoriserRefusesAPinWithoutCode() external {
        vm.chainId(LibSafeInvariants.ROBINHOOD_CHAIN_ID);
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(AuthoriserNotReady.selector, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD)
        );
        harness.callActiveChainAuthoriser();
    }

    /// @notice A pin carrying bytecode other than the EIP-1167 clone is
    /// refused: address and code presence are not enough either.
    function testActiveChainAuthoriserRefusesForeignCode() external {
        vm.chainId(LibSafeInvariants.BSC_CHAIN_ID);
        address pin = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC;
        vm.etch(pin, hex"FE");
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(abi.encodeWithSelector(AuthoriserNotReady.selector, pin));
        harness.callActiveChainAuthoriser();
    }

    /// @notice An unpinned chain reverts typed rather than resolving to
    /// another chain's clone.
    function testActiveChainAuthoriserRefusesAnUnknownChain() external {
        vm.chainId(123456);
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForAuthoriser.selector, uint256(123456)));
        harness.callActiveChainAuthoriser();
    }

    /// @notice `assertAll` reverts `AuthoriserImplCodehashMismatch` when the
    /// clone's runtime codehash drifts from the pinned EIP-1167 runtime.
    /// Simulated by etching alien bytecode over the pinned clone address.
    function testAssertAllRejectsWrongCodehash() external {
        LibLocalProdState.authorisers(vm, LibSafeInvariants.BASE_CHAIN_ID);
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        vm.etch(clone, hex"600160005260206000f3");
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthoriserImplCodehashMismatch.selector,
                clone,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
                clone.codehash
            )
        );
        harness.callAssertAll();
    }

    /// @notice The admin-holder parameterisation: the seven `_ADMIN` entries
    /// track `adminHolder`, the eight operational entries stay split between
    /// the Safe, the service signer and the orchestrator, and the no-arg
    /// Base map is exactly the widest one at Base's Safe and timelock (so no
    /// consumer can drift from the single map).
    function testExpectedGrantsAdminHolderParameterisation() external pure {
        address safe = address(0x5AFE);
        address timelock = address(0x7135);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        assertEq(grants.length, 13);
        for (uint256 i = 0; i < 7; i++) {
            assertEq(grants[i].grantee, timelock, "admin entries must track adminHolder");
        }
        for (uint256 i = 7; i < 10; i++) {
            assertEq(grants[i].grantee, safe, "operational Safe entries must track the Safe");
        }
        assertEq(grants[10].role, keccak256("CERTIFY"));
        assertEq(grants[10].grantee, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        // The orchestrator's vault access: DEPOSIT and WITHDRAW only (no
        // CERTIFY surface), independent of both parameters.
        assertEq(grants[11].role, keccak256("DEPOSIT"));
        assertEq(grants[11].grantee, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        assertEq(grants[12].role, keccak256("WITHDRAW"));
        assertEq(grants[12].grantee, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);

        // The no-arg overload is Base's Safe and Base's timelock.
        RoleGrant[] memory base = LibAuthoriserInvariants.expectedGrants();
        RoleGrant[] memory widened = LibAuthoriserInvariants.expectedGrants(
            LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK
        );
        assertEq(base.length, widened.length);
        for (uint256 i = 0; i < base.length; i++) {
            assertEq(base[i].role, widened[i].role);
            assertEq(base[i].grantee, widened[i].grantee);
        }
    }

    /// @notice `assertExpectedGrants(authoriser, safe, adminHolder)` pinpoints
    /// a missing `_ADMIN` on the timelock.
    function testAssertExpectedGrantsWithDistinctAdminHolder() external {
        LibLocalProdState.authorisers(vm, LibSafeInvariants.BASE_CHAIN_ID);
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address safe = LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE;
        address timelock = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);

        vm.mockCall(
            clone, abi.encodeWithSelector(IAccessControl.hasRole.selector, grants[0].role, timelock), abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, grants[0].role, timelock));
        harness.callAssertExpectedGrants(clone, safe, timelock);
    }

    /// @notice The orchestrator rows are strict like every other row, under
    /// every production chain id alike: a revoked orchestrator `WITHDRAW`
    /// red-lines as `ExpectedGrantMissing` naming the orchestrator. Driven
    /// on local Base state with the chain id switched, so the row state is
    /// the same under each id.
    function testAssertExpectedGrantsRejectsARevokedOrchestratorGrant() external {
        LibLocalProdState.authorisers(vm, LibSafeInvariants.BASE_CHAIN_ID);
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.mockCall(
            clone,
            abi.encodeWithSelector(IAccessControl.hasRole.selector, keccak256("WITHDRAW"), orchestrator),
            abi.encode(false)
        );
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 i = 0; i < chainIds.length; i++) {
            vm.chainId(chainIds[i]);
            vm.expectRevert(
                abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, keccak256("WITHDRAW"), orchestrator)
            );
            harness.callAssertExpectedGrants(clone);
        }
    }

    function assertBaseEuGrants(LibAuthoriserInvariantsHarness harness) internal view {
        harness.callAssertExpectedEuGrants(
            LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
    }

    function testAssertExpectedEuGrantsRejectsMissingServiceSignerCertify() external {
        LibLocalProdState.authorisers(vm, LibSafeInvariants.BASE_CHAIN_ID);
        address clone = LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE;
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.mockCall(clone, abi.encodeCall(IAccessControl.hasRole, (keccak256("CERTIFY"), signer)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, keccak256("CERTIFY"), signer));
        assertBaseEuGrants(harness);
    }

    /// @notice Base's V4 clone with the pinned codehash and the Base map
    /// passes the focused authoriser bundle.
    function testAssertAllPassesOnLocalBase() external {
        LibLocalProdState.authorisers(vm, LibSafeInvariants.BASE_CHAIN_ID);
        LibAuthoriserInvariants.assertAll();
    }

    /// @notice Every chain's pinned EU clone, deployed over the audited
    /// implementation, passes.
    function testAssertEuAuthoriserDeployedOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.authorisers(vm, chainIds[i]);
            LibAuthoriserInvariants.assertEuAuthoriserDeployed(chainIds[i]);
            vm.revertToState(snapshot);
        }
    }

    /// @notice Every chain's US clone holding that chain's map passes the
    /// three-argument grant assertion with that chain's Safe and timelock.
    function testAssertExpectedGrantsHoldsOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.clearMockedCalls();
            LibLocalProdState.authorisers(vm, chainIds[i]);
            LibAuthoriserInvariants.assertExpectedGrants(
                LibAuthoriserInvariants.authoriserForChainId(chainIds[i]),
                LibSafeInvariants.safeForChainId(chainIds[i]),
                LibTimelockInvariants.timelockForChainId(chainIds[i])
            );
            vm.revertToState(snapshot);
        }
    }

    /// @notice Every chain's EU clone holding the EU map passes with that
    /// chain's timelock as admin holder and the EU minter.
    function testAssertExpectedEuGrantsHoldsOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.clearMockedCalls();
            LibLocalProdState.authorisers(vm, chainIds[i]);
            LibAuthoriserInvariants.assertExpectedEuGrants(
                LibAuthoriserInvariants.euAuthoriserForChainId(chainIds[i]),
                LibTimelockInvariants.timelockForChainId(chainIds[i]),
                LibAuthoriserInvariants.GRANTEE_EU_MINTER
            );
            vm.revertToState(snapshot);
        }
    }
}
