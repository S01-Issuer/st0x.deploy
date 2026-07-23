// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {
    ProvisionAdditionalServiceSigner,
    AdditionalSignerAlreadyProvisioned
} from "../../script/20260723-provision-additional-service-signer.s.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title ProvisionAdditionalServiceSignerTest
/// @notice Live-fork coverage for the additional-service-signer
/// provisioning authoring, on both chains carrying a live authoriser.
/// Happy paths go red per chain once the bundle EXECUTES there
/// (`AdditionalSignerAlreadyProvisioned`); the post-execution pin PR
/// retires them. The canonical pairs are the signer's rows of
/// `LibAuthoriserInvariants.expectedGrants()`, so the suite and the
/// live-state invariants can never drift apart.
contract ProvisionAdditionalServiceSignerTest is Test {
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    bytes32 internal constant DEPOSIT = keccak256("DEPOSIT");
    bytes32 internal constant WITHDRAW = keccak256("WITHDRAW");
    bytes32 internal constant CERTIFY = keccak256("CERTIFY");

    /// @notice Drive `run()` on the active fork and assert via fork state
    /// (the artifact path is shared across parallel tests, so file contents
    /// are not asserted): every canonical additional pair was simulated onto
    /// the authoriser — the exact state `assertExpectedGrants`' union leg
    /// demands, and the pre-existing (unmocked) service signer is untouched.
    function assertRunProvisionsOnActiveFork(address authoriser) internal {
        ProvisionAdditionalServiceSigner script = new ProvisionAdditionalServiceSigner();
        script.run();

        IAccessControl acl = IAccessControl(authoriser);
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(address(1));
        uint256 pairs = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee != SIGNER) continue;
            pairs++;
            assertTrue(acl.hasRole(all[i].role, all[i].grantee), "additional pair missing post-run");
        }
        assertEq(pairs, 3, "the canonical map carries the signer's three rows");
        assertTrue(
            acl.hasRole(DEPOSIT, LibAuthoriserInvariants.GRANTEE_SERVICE_1C66),
            "original service signer must be untouched"
        );
    }

    /// @notice The SAME script authors the provisioning on each chain
    /// carrying a live authoriser — Base then Ethereum, serially in one
    /// test (shared artifact path).
    function testRunCompletesOnBothLiveChains() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertRunProvisionsOnActiveFork(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE);

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertRunProvisionsOnActiveFork(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM);
    }

    /// @notice A fully provisioned chain refuses to author an empty bundle
    /// — the exact post-execution state. Simulated by mocking every
    /// additional pair as held.
    function testRunRevertsWhenAlreadyProvisioned() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        bytes32[3] memory roles = [DEPOSIT, WITHDRAW, CERTIFY];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.mockCall(
                authoriser, abi.encodeWithSelector(IAccessControl.hasRole.selector, roles[i], SIGNER), abi.encode(true)
            );
        }
        ProvisionAdditionalServiceSigner script = new ProvisionAdditionalServiceSigner();
        vm.expectRevert(AdditionalSignerAlreadyProvisioned.selector);
        script.run();
    }

    /// @notice Partial execution recovers by re-dispatch: with CERTIFY
    /// already held (mocked), only the remaining pairs are authored, and the
    /// fork state proves it — DEPOSIT/WITHDRAW genuinely granted (DEPOSIT
    /// also drives the n+1 walk), CERTIFY untouched on the real fork.
    function testRunAuthorsOnlyTheMissingPairs() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        vm.mockCall(
            authoriser, abi.encodeWithSelector(IAccessControl.hasRole.selector, CERTIFY, SIGNER), abi.encode(true)
        );
        ProvisionAdditionalServiceSigner script = new ProvisionAdditionalServiceSigner();
        script.run();

        vm.clearMockedCalls();
        IAccessControl acl = IAccessControl(authoriser);
        assertTrue(acl.hasRole(DEPOSIT, SIGNER), "missing DEPOSIT pair was authored");
        assertTrue(acl.hasRole(WITHDRAW, SIGNER), "missing WITHDRAW pair was authored");
        assertFalse(acl.hasRole(CERTIFY, SIGNER), "already-held CERTIFY must not be re-authored");
    }
}
