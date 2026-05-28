// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdDeployV3} from "../../../../src/lib/LibProdDeployV3.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title StoxProdV3Test
/// @notice Post-deploy integrity pin for the V3 corporate-actions
/// implementations. Mirrors `StoxProdV2Test::checkAllV2OnChain`: a per-network
/// fork that asserts the deterministic V3 artifacts exist at their Zoltu
/// addresses with the pinned (audited) codehash.
///
/// The two artifacts pinned here are the only contracts the V3 corporate-
/// actions upgrade introduces as new bytecode on-chain:
///
/// - `LibProdDeployV3.STOX_RECEIPT_VAULT` — the V3 receipt vault
///   implementation whose `fallback()` delegatecalls into the corporate-
///   actions facet. (The Zoltu address is unchanged from V2, but the bytecode
///   — and therefore the codehash — differs: V3 adds the corporate-actions
///   fallback.)
/// - `LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET` — the facet the vault's
///   fallback routes corporate-action selectors into.
///
/// Every other V3 deploy constant (deployers, beacons, authorisers) is
/// unchanged from V2 and already pinned by `StoxProdV2Test`, so it is not
/// re-pinned here.
///
/// @dev **These tests FAIL until the V3 implementations are deployed on-chain
/// via the Zoltu deterministic deployer.** That is expected and intentional:
/// this PR is opened as a DRAFT and merges only once the V3 bytecode is live,
/// at which point the pins go green automatically — the same "fails until live
/// execution" pattern as the RAI-296 post-migration pin (PR #194). The pins
/// give the V3 deployment the same per-push CI integrity coverage that V2
/// deployments get.
contract StoxProdV3Test is Test {
    /// @notice Assert both V3 artifacts are deployed at their deterministic
    /// addresses with the pinned codehash on the active fork. The Zoltu
    /// deploy is identical across every EVM network, so this same check runs
    /// per-network.
    function checkAllV3OnChain() internal view {
        assertTrue(LibProdDeployV3.STOX_RECEIPT_VAULT.code.length > 0, "V3 StoxReceiptVault not deployed");
        assertEq(
            LibProdDeployV3.STOX_RECEIPT_VAULT.codehash,
            LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH,
            "V3 StoxReceiptVault codehash mismatch"
        );

        assertTrue(
            LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET.code.length > 0, "V3 StoxCorporateActionsFacet not deployed"
        );
        assertEq(
            LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET.codehash,
            LibProdDeployV3.STOX_CORPORATE_ACTIONS_FACET_CODEHASH,
            "V3 StoxCorporateActionsFacet codehash mismatch"
        );
    }

    /// V3 implementations MUST be deployed on Arbitrum.
    function testProdDeployArbitrumV3() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        checkAllV3OnChain();
    }

    /// V3 implementations MUST be deployed on Base. Base is the network where
    /// the live receipt vaults are upgraded to V3.
    function testProdDeployBaseV3() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        checkAllV3OnChain();
    }

    /// V3 implementations MUST be deployed on Base Sepolia.
    function testProdDeployBaseSepoliaV3() external {
        vm.createSelectFork(LibRainDeploy.BASE_SEPOLIA);
        checkAllV3OnChain();
    }

    /// V3 implementations MUST be deployed on Flare.
    function testProdDeployFlareV3() external {
        vm.createSelectFork(LibRainDeploy.FLARE);
        checkAllV3OnChain();
    }

    /// V3 implementations MUST be deployed on Polygon.
    function testProdDeployPolygonV3() external {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        checkAllV3OnChain();
    }
}
