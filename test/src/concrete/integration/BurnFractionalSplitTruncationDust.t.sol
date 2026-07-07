// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";

import {IST0xOrchestratorV1, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title BurnFractionalSplitTruncationDustTest
/// @notice Workflow: a 1:3 reverse split truncates the receipt side per-id
/// but the share side per-account, leaving the held receipts short of the
/// rebased share balance by one unit. Burning the full balance REVERTS
/// `InsufficientReceipts(token, gap)` — the orchestrator never mints to cover
/// a shortfall. Burning only what the receipts cover succeeds, and the
/// truncation-dust share stays with the holder for manual recovery.
contract BurnFractionalSplitTruncationDustTest is OrchestratorIntegrationTest {
    function testBurnAfterFractionalSplitRevertsOnTruncationDust() external {
        (address eoa, uint256 pkA) = makeAddrAndKey("frac-recipient");

        // Two separate small receipts, each of which truncates on a 1/3
        // multiplier: trunc(5/3) == 1 per id, but trunc(10/3) == 3 for the
        // account-level share balance — a 1-unit gap.
        MintAuthV1 memory authA = _signedMintAuth(address(vault), eoa, 5, keccak256("fa"), pkA);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 5, authA, "");
        MintAuthV1 memory authB = _signedMintAuth(address(vault), eoa, 5, keccak256("fb"), pkA);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 5, authB, "");
        uint256 idA = 1;
        uint256 idB = 2;
        assertEq(vault.highwaterId(), idB, "two receipts minted");

        _scheduleAndCompleteSplit(
            LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(3, 0))
        );

        uint256 burnAmount = vault.balanceOf(eoa);
        uint256 receiptTotal =
            receipt.balanceOf(address(orchestrator), idA) + receipt.balanceOf(address(orchestrator), idB);
        assertEq(burnAmount, 3, "account-level share truncation: trunc(10 * 1/3) == 3");
        assertEq(receiptTotal, 2, "per-id receipt truncation: trunc(5 * 1/3) * 2 == 2");
        uint256 gap = burnAmount - receiptTotal;
        assertGt(gap, 0, "scenario must produce truncation dust");

        vm.prank(eoa);
        assertTrue(IERC20(address(vault)).transfer(MM, burnAmount), "hand shares to the burner");
        vm.prank(MM);
        IERC20(address(vault)).approve(address(orchestrator), burnAmount);

        // Burning the full rebased balance overruns the held receipts by
        // `gap` → the whole burn reverts; nothing is pulled or consumed.
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.InsufficientReceipts.selector, address(vault), gap));
        orchestrator.burn(address(vault), burnAmount, "");

        assertEq(vault.balanceOf(MM), burnAmount, "reverted burn pulled nothing");
        assertEq(receipt.balanceOf(address(orchestrator), idA), 1, "receipt idA untouched");
        assertEq(receipt.balanceOf(address(orchestrator), idB), 1, "receipt idB untouched");

        // Burning only what the receipts cover succeeds; the dust share
        // stays with the burner awaiting manual recovery (e.g. receipts
        // transferred in, which auto-lower the pointer).
        vm.prank(MM);
        orchestrator.burn(address(vault), receiptTotal, "");

        assertEq(vault.balanceOf(MM), gap, "burner keeps exactly the truncation dust");
        assertEq(receipt.balanceOf(address(orchestrator), idA), 0, "receipt idA consumed");
        assertEq(receipt.balanceOf(address(orchestrator), idB), 0, "receipt idB consumed");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded on the orchestrator");
        // The walk starts at 0 (id 0 empty), consumes ids 1 and 2 fully, and
        // ends one past the last consumed id.
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), idB + 1, "pointer one past the last consumed id");
        assertEq(vault.totalSupply(), gap, "only the dust remains outstanding");
    }
}
