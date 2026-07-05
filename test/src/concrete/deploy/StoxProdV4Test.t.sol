// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../../../src/lib/LibProdDeployV4.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title StoxProdV4Test
/// @notice Post-deploy + post-swap integrity pin for V4 on-chain state.
/// Two pin layers:
///
/// **Layer 1 — V4 bytecode integrity (per-network).** The deterministic V4
/// receipt vault implementation and the V4 corporate-actions facet must exist
/// at their post-rebuild Zoltu addresses with the audited V4 codehash. Mirrors
/// the V2 / V3 patterns of `checkAllV{N}OnChain` and runs against every EVM
/// network the ST0x deploy targets, since the Zoltu deploy is identical
/// across them.
///
/// **Layer 2 — Post-swap authoriser state (Base only).** After the V4 upgrade
/// + authoriser swap script (in `script/UpgradeReceiptVaultsToV4.s.sol`) lands
/// on Base:
/// - every production receipt vault's `authorizer()` returns the V4 clone
///   (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`);
/// - the V4 clone's `(role, grantee)` map matches
///   `LibAuthoriserInvariants.expectedGrants()` exactly.
/// These are Base-only because no other network carries live production
/// receipt vaults.
///
/// @dev **All assertions FAIL until the V4 placeholders in `LibProdDeployV4`
/// and `LibAuthoriserInvariants` are hydrated AND the resulting V4 impl + facet are
/// Zoltu-deployed AND the V4 clone is deployed + initialised + grant-mirrored
/// AND the upgrade + swap script has executed on Base.** That is intentional:
/// this PR is opened as a DRAFT and merges only once each of those steps has
/// landed on the relevant network, at which point the pins go green
/// automatically — the same "fails until live execution" pattern as the
/// RAI-296 post-migration pin (PR #194) and the V3 predecessor.
///
/// Once the placeholders are hydrated (`RAIN_VATS_0_1_6` → real tag, address(0)
/// → real address, bytes32(0) → real codehash) every assertion here goes from
/// trivially-red to a genuine drift detector against the live chain.
contract StoxProdV4Test is Test {
    /// @notice Assert both V4 artifacts (receipt vault impl + corporate-
    /// actions facet) are deployed at their deterministic addresses with the
    /// pinned codehash on the active fork. The Zoltu deploy is identical
    /// across every EVM network, so this same check runs per-network.
    function checkAllV4OnChain() internal view {
        assertTrue(
            LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6.code.length > 0, "V4 StoxReceiptVault impl not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_0_1_6,
            "V4 StoxReceiptVault impl codehash mismatch"
        );

        assertTrue(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6.code.length > 0,
            "V4 StoxCorporateActionsFacet not deployed"
        );
        assertEq(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_RAIN_VATS_0_1_6.codehash,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_RAIN_VATS_0_1_6,
            "V4 StoxCorporateActionsFacet codehash mismatch"
        );
    }

    /// @notice Assert the post-swap authoriser state on Base: every prod
    /// receipt vault's `authorizer()` returns the V4 clone, and the V4 clone
    /// holds every `LibAuthoriserInvariants.expectedGrants()` pair. Base-only.
    function checkPostSwapAuthoriserStateOnBase() internal view {
        address v4Clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        assertTrue(v4Clone != address(0), "V4 authoriser clone still placeholder");
        assertTrue(v4Clone.code.length > 0, "V4 authoriser clone not deployed");
        assertEq(
            v4Clone.codehash,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            "V4 authoriser clone codehash mismatch"
        );

        // Every prod receipt vault's authoriser is the V4 clone.
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            address actual = address(IAuthorizableV1(vaults[i]).authorizer());
            assertEq(actual, v4Clone, "vault.authorizer() != V4 clone");
        }

        // V4 clone carries the expected role-grant map exactly.
        IAccessControl cloneAcl = IAccessControl(v4Clone);
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < grants.length; i++) {
            assertTrue(cloneAcl.hasRole(grants[i].role, grants[i].grantee), "V4 clone missing expected grant");
        }
    }

    /// V4 implementations MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV4() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Base + the upgrade + authoriser
    /// swap MUST have landed against live prod vaults.
    function testProdDeployBaseV4() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV4OnChain();
        checkPostSwapAuthoriserStateOnBase();
    }

    /// V4 implementations MUST be deployed on Base Sepolia.
    function testProdDeployBaseSepoliaV4() external {
        vm.createSelectFork(LibRainDeploy.BASE_SEPOLIA);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Flare.
    function testProdDeployFlareV4() external {
        vm.createSelectFork(LibRainDeploy.FLARE);
        checkAllV4OnChain();
    }

    /// V4 implementations MUST be deployed on Polygon.
    function testProdDeployPolygonV4() external {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        checkAllV4OnChain();
    }
}
