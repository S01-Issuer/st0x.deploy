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
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title ProvisionAdditionalServiceSignerProdTest
/// @notice PROD coverage for the additional-service-signer provisioning:
/// what production IS on each chain carrying a live V4 authoriser, read
/// from a real fork with no mocks anywhere.
///
/// The provisioning has EXECUTED on both chains — the Safe signed it — so
/// each chain's authoriser holds all three canonical pairs and the script
/// refuses to author an empty bundle there. That refusal is the assertion:
/// a chain that stops holding a pair (a revoke, a swapped authoriser) goes
/// red here, because `run()` would find work to do again.
///
/// @dev No mocks. Each chain's state is whatever the chain says it is; a
/// mocked fork fixture is a premise the next legitimate operation deletes,
/// which is precisely what retired the mocked predecessors of this file.
/// Selection logic — which pairs get authored for a given role state — is
/// covered without a fork in
/// `20260723-provision-additional-service-signer.t.sol`.
///
/// The shared `out/` artifact path is not a constraint here: `run()`
/// reverts during pre-flight on a provisioned chain, so no test in this
/// file reaches the artifact write.
///
/// The whole-map sweep (every `expectedGrants()` row, plus the negative
/// `DEFAULT_ADMIN_ROLE` assertion over the pinned grantees) already runs
/// per chain in `test/src/concrete/deploy/StoxCrossChainParity.t.sol` and
/// is deliberately not duplicated here; this file asserts the slice this
/// script owns.
contract ProvisionAdditionalServiceSignerProdTest is Test {
    /// @notice The signer this operation provisions.
    address internal constant SIGNER = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;

    /// @notice Assert the ACTIVE fork is fully provisioned for the
    /// additional signer: every canonical pair of the signer holds on the
    /// chain's authoriser, and the script refuses to author against it.
    /// @param label Human chain name, surfaced in assertion messages.
    /// @param authoriser The chain's pinned V4 authoriser clone.
    /// @param safe The chain's token-owner Safe, filling the map's Safe
    /// grantee slots.
    function assertActiveForkProvisioned(string memory label, address authoriser, address safe) internal {
        IAccessControl acl = IAccessControl(authoriser);
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants(safe);
        uint256 pairs = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].grantee != SIGNER) continue;
            pairs++;
            assertTrue(
                acl.hasRole(all[i].role, all[i].grantee),
                string.concat(label, ": additional signer is missing a canonical pair")
            );
        }
        assertEq(pairs, 3, "the canonical map carries the signer's three rows");

        // Nothing left to author on this chain. `run()` reaches the
        // refusal only after its full pre-flight passes, so this also
        // pins the Safe, the authoriser pin + codehash, and the rest of
        // the grant map on the live chain.
        ProvisionAdditionalServiceSigner script = new ProvisionAdditionalServiceSigner();
        vm.expectRevert(AdditionalSignerAlreadyProvisioned.selector);
        script.run();
    }

    /// @notice Base is provisioned.
    function testBaseIsProvisioned() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertActiveForkProvisioned(
            "Base", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE
        );
    }

    /// @notice Ethereum is provisioned.
    function testEthereumIsProvisioned() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertActiveForkProvisioned(
            "Ethereum",
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM
        );
    }
}
