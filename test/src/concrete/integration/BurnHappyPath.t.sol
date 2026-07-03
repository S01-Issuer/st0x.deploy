// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";

import {IST0xOrchestratorV1, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title BurnHappyPathTest
/// @notice Workflow: MM mints to an EOA, the EOA approves the orchestrator,
/// MM burns the full amount. The recipient is drained, the receipt consumed,
/// and the burn walk — starting from the fresh token's pointer at 0 — steps
/// over the empty id 0, consumes id 1, and lands one past it.
contract BurnHappyPathTest is OrchestratorIntegrationTest {
    function testBurnHappyPathAndPointer() external {
        (address eoa, uint256 pk) = makeAddrAndKey("burn-recipient");
        uint256 amount = 55e18;
        bytes32 nonce = keccak256("burn");

        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "");
        uint256 mintedId = vault.highwaterId();
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), 0, "fresh token's pointer starts at 0");

        vm.prank(eoa);
        IERC20(address(vault)).approve(address(orchestrator), amount);

        // The walk starts at 0 (skipping the zero-balance id 0) and ends one
        // past the consumed id, so the consumed range is [0, mintedId + 1).
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Burned(MM, address(vault), eoa, amount, 0, mintedId + 1);
        vm.prank(MM);
        orchestrator.burn(address(vault), eoa, amount, "");

        assertEq(vault.balanceOf(eoa), 0, "recipient drained");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt consumed");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded");
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), mintedId + 1, "pointer advanced one past consumed id");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");
    }
}
