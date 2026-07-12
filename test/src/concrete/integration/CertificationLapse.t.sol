// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {CertificationExpired} from "rain-vats-0.1.7/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title CertificationLapseTest
/// @notice Workflow: once certification lapses, the orchestrator halts
/// entirely. Mints revert on the ERC-20 forward leg (orchestrator -> to) and
/// burns revert on the pull leg (caller -> orchestrator) — both surface the
/// authoriser's `CertificationExpired`. Loud halt, no silent partial
/// operation; the issuer re-certifies to resume.
contract CertificationLapseTest is OrchestratorIntegrationTest {
    function testCertificationLapseHaltsMintAndBurn() external {
        (address eoa, uint256 pk) = makeAddrAndKey("cert-recipient");

        // Pre-lapse external mint to an EOA succeeds.
        uint256 minted = 10e18;
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, minted, keccak256("c0"), pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, minted, auth, "");

        // Hand the shares to the burner and approve pre-lapse, so the only
        // thing standing between MM and a burn is the certification.
        vm.prank(eoa);
        assertTrue(IERC20(address(vault)).transfer(MM, minted), "hand shares to the burner");
        vm.prank(MM);
        IERC20(address(vault)).approve(address(orchestrator), type(uint256).max);

        // Lapse certification. setUp certified until t = 1_000_000; expiry is
        // strict `>`.
        vm.warp(1_000_001);
        assertTrue(vault.isCertificationExpired(), "certification must have lapsed");

        // External mint reverts on the ERC-20 forward leg.
        MintAuthV1 memory extAuth = _signedMintAuth(address(vault), eoa, 1e18, keccak256("c1"), pk);
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, address(orchestrator), eoa));
        orchestrator.mint(address(vault), eoa, 1e18, extAuth, "");

        // Burn reverts on the pull leg (caller -> orchestrator).
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, MM, address(orchestrator)));
        orchestrator.burn(address(vault), 3e18, "");
    }
}
