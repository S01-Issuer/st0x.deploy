// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {
    LibAuthoriserInvariants,
    RoleGrant,
    AuthoriserNotReady,
    UnsupportedChainForAuthoriser,
    ExpectedGrantMissing,
    UnexpectedDefaultAdmin,
    UnexpectedRetainedAdminGrant,
    UnexpectedRetiredSignerGrant,
    AuthoriserImplCodehashMismatch
} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariantsHarness} from "./LibAuthoriserInvariantsHarness.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";

/// @title LibAuthoriserInvariantsTest
/// @notice Fork tests pinning the production V4 authoriser clone's state
/// against the constants in `LibAuthoriserInvariants`. The positive case
/// runs the lib's no-arg `assertAll()`, which checks the clone's codehash
/// against the `LibProdDeployV4` pin and iterates the master
/// `expectedGrants()` map against the live clone. Any drift (a grant
/// missing on-chain, or the clone's bytecode changing) surfaces as a typed
/// error here.
/// @dev Uses unpinned head forks of each production chain (same precedent
/// as the other prod-state drift detectors in this repo). Pinning would freeze the
/// invariant assertions against a stale snapshot and let new drift slip
/// through unnoticed.
contract LibAuthoriserInvariantsTest is Test {
    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Live drift detector; see contract-level rationale.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice The production V4 clone pinned in `LibProdDeployV4` holds
    /// every `expectedGrants()` pair and its codehash matches the pin.
    /// Passes against the live chain state.
    function testAssertAllPasses() external {
        selectBaseFork();
        LibAuthoriserInvariants.assertAll();
    }

    /// @notice The four factory-derived clone pins are the first CREATE from
    /// the canonical CloneFactory (nonce 1) on each chain, re-derived here so a
    /// mistyped literal fails fork-free. Base's clone came from a factory with
    /// history and is not derivable.
    function testClonePinsMatchTheFactoryNonceOneDerivation() external pure {
        address derived = vm.computeCreateAddress(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS, 1);
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

    /// @notice The active fork's arm resolves to a live clone with the pinned
    /// EIP-1167 codehash, on the canonical grant map keyed to that chain's
    /// Safe. Both resolve from `block.chainid`, as the scripts do, so a leg
    /// forking the wrong chain or an arm pointing at the wrong slot fails
    /// here. Live drift detector on an unpinned fork.
    function assertAuthoriserLiveOnCanonicalMap() internal view {
        LibAuthoriserInvariants.assertExpectedGrants(
            LibAuthoriserInvariants.activeChainAuthoriser(), LibSafeInvariants.safeForChainId(block.chainid)
        );
    }

    function testBaseAuthoriserIsLiveOnTheCanonicalMap() external {
        selectBaseFork();
        assertAuthoriserLiveOnCanonicalMap();
    }

    function testEthereumAuthoriserIsLiveOnTheCanonicalMap() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertAuthoriserLiveOnCanonicalMap();
    }

    function testHyperEvmAuthoriserIsLiveOnTheCanonicalMap() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertAuthoriserLiveOnCanonicalMap();
    }

    function testRobinhoodAuthoriserIsLiveOnTheCanonicalMap() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertAuthoriserLiveOnCanonicalMap();
    }

    function testBscAuthoriserIsLiveOnTheCanonicalMap() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertAuthoriserLiveOnCanonicalMap();
    }

    /// @notice `assertAll` reverts `AuthoriserImplCodehashMismatch` when the
    /// clone's runtime codehash drifts from the pinned EIP-1167 runtime.
    /// Simulated by etching alien bytecode over the pinned clone address.
    function testAssertAllRejectsWrongCodehash() external {
        selectBaseFork();
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

    /// @notice `assertExpectedGrants` reverts `UnexpectedDefaultAdmin` when a
    /// pinned grantee holds `DEFAULT_ADMIN_ROLE`.
    function testAssertExpectedGrantsRejectsDefaultAdmin() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        vm.mockCall(
            clone,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector, bytes32(0), LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE
            ),
            abi.encode(true)
        );
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedDefaultAdmin.selector, clone, LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE
            )
        );
        harness.callAssertExpectedGrants(clone);
    }

    /// @notice The admin-holder parameterisation: the seven `_ADMIN` entries
    /// track `adminHolder`, the eight operational entries stay split between
    /// the Safe, the service signer and the orchestrator, and the narrower
    /// overloads are exact collapses of the widest one (so no consumer can
    /// drift from the single map).
    function testExpectedGrantsAdminHolderParameterisation() external pure {
        address safe = address(0x5AFE);
        address timelock = address(0x7135);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        assertEq(grants.length, 15);
        for (uint256 i = 0; i < 7; i++) {
            assertEq(grants[i].grantee, timelock, "admin entries must track adminHolder");
        }
        for (uint256 i = 7; i < 10; i++) {
            assertEq(grants[i].grantee, safe, "operational Safe entries must track the Safe");
        }
        // The service signer's three action roles are operational, not
        // admin: they must track the signer regardless of who holds the
        // `_ADMIN` slice, so the timelock migration never moves them. The
        // retired signer has no rows at all — its revocation is asserted as
        // an absence, not a grant.
        for (uint256 i = 10; i < 13; i++) {
            assertEq(
                grants[i].grantee,
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C,
                "service signer entries must be independent of adminHolder"
            );
        }
        // The orchestrator's vault access: DEPOSIT and WITHDRAW only (no
        // CERTIFY surface), independent of both parameters.
        assertEq(grants[13].role, keccak256("DEPOSIT"));
        assertEq(grants[13].grantee, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        assertEq(grants[14].role, keccak256("WITHDRAW"));
        assertEq(grants[14].grantee, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);

        // The two-arg overload is the adminHolder == Safe collapse.
        RoleGrant[] memory collapsed = LibAuthoriserInvariants.expectedGrants(safe);
        RoleGrant[] memory widened = LibAuthoriserInvariants.expectedGrants(safe, safe);
        assertEq(collapsed.length, widened.length);
        for (uint256 i = 0; i < collapsed.length; i++) {
            assertEq(collapsed[i].role, widened[i].role);
            assertEq(collapsed[i].grantee, widened[i].grantee);
        }
    }

    /// @notice `assertExpectedGrants(authoriser, safe, adminHolder)` demands
    /// the exact post-timelock-migration shape: it pinpoints the first
    /// missing `_ADMIN` grant while the admin holder holds nothing, rejects
    /// the dual-holder state where the Safe retains an `_ADMIN` copy
    /// alongside the admin holder (an instant delay bypass), and passes only
    /// once the seven `_ADMIN` roles sit exclusively on the admin holder.
    function testAssertExpectedGrantsWithDistinctAdminHolder() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address safe = LibAuthoriserInvariants.GRANTEE_TOKEN_OWNER_SAFE;
        address timelock = address(0x7135);
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();

        // Without the timelock holding anything, the first `_ADMIN` entry is
        // reported missing for the timelock.
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, grants[0].role, timelock));
        harness.callAssertExpectedGrants(clone, safe, timelock);

        // Mock the seven `_ADMIN` grants onto the timelock. The live fork's
        // Safe still holds its `_ADMIN` copies, so this is the dual-holder
        // state — the Safe could still mutate the grant map without the
        // timelock's delay — and the assertion must reject it.
        for (uint256 i = 0; i < 7; i++) {
            vm.mockCall(
                clone,
                abi.encodeWithSelector(IAccessControl.hasRole.selector, grants[i].role, timelock),
                abi.encode(true)
            );
        }
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRetainedAdminGrant.selector, clone, grants[0].role, safe));
        harness.callAssertExpectedGrants(clone, safe, timelock);

        // Mock the Safe's seven `_ADMIN` copies away — the renounces landing
        // — and the full assertion passes: exclusive admin holding, with the
        // operational entries already live on the fork.
        for (uint256 i = 0; i < 7; i++) {
            vm.mockCall(
                clone, abi.encodeWithSelector(IAccessControl.hasRole.selector, grants[i].role, safe), abi.encode(false)
            );
        }
        harness.callAssertExpectedGrants(clone, safe, timelock);
    }

    /// @notice A re-grant to the retired signer is refused: the revocation
    /// is pinned as an absence, so any action role landing back on
    /// `GRANTEE_SERVICE_1C66` red-lines with `UnexpectedRetiredSignerGrant`
    /// naming the role.
    function testAssertExpectedGrantsRefusesARetiredSignerRegrant() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();

        vm.mockCall(
            clone,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector, keccak256("WITHDRAW"), LibAuthoriserInvariants.GRANTEE_SERVICE_1C66
            ),
            abi.encode(true)
        );
        vm.expectRevert(abi.encodeWithSelector(UnexpectedRetiredSignerGrant.selector, clone, keccak256("WITHDRAW")));
        harness.callAssertExpectedGrants(clone);
    }

    /// @notice The orchestrator rows are strict like every other row, under
    /// every production chain id alike: a revoked orchestrator `WITHDRAW`
    /// red-lines as `ExpectedGrantMissing` naming the orchestrator. Driven
    /// on the Base fork with the chain id switched, so the row state is the
    /// same under each id.
    function testAssertExpectedGrantsRejectsARevokedOrchestratorGrant() external {
        selectBaseFork();
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

    /// @notice The orchestrator is a pinned grantee, so it joins the
    /// `DEFAULT_ADMIN_ROLE` negative: root admin on the orchestrator
    /// red-lines as `UnexpectedDefaultAdmin` naming it.
    function testAssertExpectedGrantsRejectsOrchestratorDefaultAdmin() external {
        selectBaseFork();
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
        vm.mockCall(
            clone, abi.encodeWithSelector(IAccessControl.hasRole.selector, bytes32(0), orchestrator), abi.encode(true)
        );
        LibAuthoriserInvariantsHarness harness = new LibAuthoriserInvariantsHarness();
        vm.expectRevert(abi.encodeWithSelector(UnexpectedDefaultAdmin.selector, clone, orchestrator));
        harness.callAssertExpectedGrants(clone);
    }
}
