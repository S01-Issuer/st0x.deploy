// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";

import {IST0xOrchestratorV1, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title ReceiptTransferInLowersPointerTest
/// @notice Workflow (ops bootstrap): receipts exist at low ids held OUTSIDE
/// the orchestrator while its burn pointer has already advanced past them.
/// The holder `safeTransferFrom`s the receipt back in; the ERC-1155 receiver
/// hook proves it is a genuine production receipt (its `manager()` vault's
/// `receipt()` round-trips), lowers the pointer to the arriving id, and emits
/// `BurnIndexLowered` — so a subsequent burn covers the outstanding shares
/// WITHOUT any `setBurnIndex` call.
contract ReceiptTransferInLowersPointerTest is OrchestratorIntegrationTest {
    address internal constant EMERGENCY = address(uint160(uint256(keccak256("EMERGENCY_OPS"))));

    function testReceiptTransferInLowersPointerAndEnablesBurn() external {
        (address eoa, uint256 pk) = makeAddrAndKey("bootstrap-recipient");
        address holder = makeAddr("receipt-holder");

        // Mint 10e18 to the EOA — receipt id 1 held by the orchestrator.
        MintAuthV1 memory authLow = _signedMintAuth(address(vault), eoa, 10e18, keccak256("b1"), pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 10e18, authLow, "");
        uint256 lowId = vault.highwaterId();
        assertEq(lowId, 1, "first mint lands at id 1");

        // EMERGENCY withdraws that receipt out to an external holder, leaving
        // the orchestrator with nothing backing the EOA's 10e18 shares.
        bytes32 emergencyRole = orchestrator.EMERGENCY_ROLE();
        vm.prank(OWNER);
        orchestrator.grantRole(emergencyRole, EMERGENCY);
        vm.prank(EMERGENCY);
        orchestrator.withdrawReceipt(address(vault), lowId, 10e18, holder);
        assertEq(receipt.balanceOf(holder, lowId), 10e18, "holder received the low receipt");

        // Advance the pointer PAST the withdrawn id with a second mint+burn:
        // the walk starts at 0, skips id 0 (empty) and id 1 (withdrawn),
        // consumes id 2 fully, and parks the pointer at 3 — above lowId.
        MintAuthV1 memory authHigh = _signedMintAuth(address(vault), eoa, 4e18, keccak256("b2"), pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, 4e18, authHigh, "");
        uint256 highId = vault.highwaterId();
        // Burns pull from the caller: hand all of the EOA's shares to MM.
        vm.prank(eoa);
        assertTrue(IERC20(address(vault)).transfer(MM, 14e18), "hand shares to the burner");
        vm.prank(MM);
        IERC20(address(vault)).approve(address(orchestrator), type(uint256).max);
        vm.prank(MM);
        orchestrator.burn(address(vault), 4e18, "");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), highId + 1, "pointer parked above the low receipt");

        // The outstanding 10e18 is unburnable: the orchestrator holds nothing
        // at or above the pointer.
        vm.prank(MM);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.InsufficientReceipts.selector, address(vault), 10e18)
        );
        orchestrator.burn(address(vault), 10e18, "");

        // The holder transfers the receipt back in. The receiver hook
        // recognises the genuine production receipt and lowers the pointer to
        // the arriving id — no setBurnIndex.
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexLowered(address(vault), highId + 1, lowId);
        vm.prank(holder);
        receipt.safeTransferFrom(holder, address(orchestrator), lowId, 10e18, "");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), lowId, "pointer auto-lowered to the transferred id");

        // The burn now covers the outstanding shares.
        vm.prank(MM);
        orchestrator.burn(address(vault), 10e18, "");
        assertEq(vault.balanceOf(MM), 0, "burner drained");
        assertEq(receipt.balanceOf(address(orchestrator), lowId), 0, "transferred-in receipt consumed");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), lowId + 1, "pointer one past the consumed id");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");
    }
}
