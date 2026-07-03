// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {CertificationExpired} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest, AcceptingMintRecipient} from "./OrchestratorIntegrationTest.sol";

/// @title CertificationLapseTest
/// @notice Workflow: once certification lapses, external mints revert on the
/// ERC-20 forward leg (`CertificationExpired`), while a self-burn — the
/// orchestrator burning its own held shares — still works because the
/// authoriser exempts the (orchestrator -> 0) redeem leg for `WITHDRAW`
/// holders and there is no external pull.
contract CertificationLapseTest is OrchestratorIntegrationTest {
    function testCertificationLapseSelfFlowsOnly() external {
        (address eoa, uint256 pk) = makeAddrAndKey("cert-recipient");

        // Pre-lapse external mint to an EOA succeeds.
        uint256 minted = 10e18;
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, minted, keccak256("c0"), pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, minted, auth, "");

        // Seed the orchestrator with self-held shares so the self-burn has
        // something to consume during the lapse. The orchestrator does not
        // implement `IMintRecipient`, so it can't authorise a mint to itself
        // directly; instead mint (pre-lapse) to a callback recipient and have
        // it forward the shares onto the orchestrator.
        AcceptingMintRecipient self = new AcceptingMintRecipient();
        uint256 selfMint = 4e18;
        vm.prank(MM);
        orchestrator.mint(address(vault), address(self), selfMint, _callbackMintAuth(keccak256("c1")), "");
        // Move those shares onto the orchestrator for a genuine self-burn.
        vm.prank(address(self));
        assertTrue(IERC20(address(vault)).transfer(address(orchestrator), selfMint), "self transfer succeeded");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), selfMint, "orchestrator holds self shares");

        // Lapse certification. setUp certified until t = 1_000_000; expiry is
        // strict `>`.
        vm.warp(1_000_001);
        assertTrue(vault.isCertificationExpired(), "certification must have lapsed");

        // External mint reverts on the ERC-20 forward leg.
        MintAuthV1 memory extAuth = _signedMintAuth(address(vault), eoa, 1e18, keccak256("c2"), pk);
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, address(orchestrator), eoa));
        orchestrator.mint(address(vault), eoa, 1e18, extAuth, "");

        // Self-burn still works: no external pull, and the redeem leg
        // (orchestrator -> 0) is exempt for WITHDRAW holders.
        uint256 supplyBefore = vault.totalSupply();
        uint256 burnAmount = 3e18;
        vm.prank(MM);
        orchestrator.burn(address(vault), address(orchestrator), burnAmount, "");
        assertEq(vault.totalSupply(), supplyBefore - burnAmount, "self-burn reduced supply");
        assertEq(
            IERC20(address(vault)).balanceOf(address(orchestrator)),
            selfMint - burnAmount,
            "self balance partially consumed"
        );
    }
}
