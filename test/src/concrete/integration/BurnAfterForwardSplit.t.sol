// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";

import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title BurnAfterForwardSplitTest
/// @notice Workflow: a 3:1 forward split rebases the recipient's shares and
/// the orchestrator's held receipt in lockstep. Burning the full rebased
/// balance drains both exactly.
contract BurnAfterForwardSplitTest is OrchestratorIntegrationTest {
    function testBurnAfterForwardSplitConsumesRebasedReceiptExactly() external {
        (address eoa, uint256 pk) = makeAddrAndKey("split-recipient");
        uint256 minted = 90e18;
        bytes32 nonce = keccak256("fwd-split");

        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, minted, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, minted, auth, "");
        uint256 mintedId = vault.highwaterId();
        assertEq(mintedId, 1, "first mint on a fresh vault lands at id 1");

        _scheduleAndCompleteSplit(LibDecimalFloat.packLossless(3, 0));

        assertEq(vault.balanceOf(eoa), 270e18, "recipient share balance rebased 3x");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 270e18, "orchestrator receipt rebased 3x");

        vm.prank(eoa);
        assertTrue(IERC20(address(vault)).transfer(MM, 270e18), "hand shares to the burner");
        vm.prank(MM);
        IERC20(address(vault)).approve(address(orchestrator), 270e18);

        vm.prank(MM);
        orchestrator.burn(address(vault), 270e18, "");

        assertEq(vault.balanceOf(eoa), 0, "recipient drained");
        assertEq(vault.balanceOf(MM), 0, "burner drained");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded");
        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt fully consumed");
        // The walk starts at 0 (id 0 has zero balance) and ends one past the
        // consumed id 1.
        assertEq(orchestrator.nextBurnReceiptId(address(vault)), mintedId + 1, "pointer advanced one past consumed id");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");
    }
}
