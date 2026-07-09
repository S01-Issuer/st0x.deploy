// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IReceiptVaultV1} from "rain-vats-0.1.6/src/interface/deprecated/IReceiptVaultV1.sol";
import {IReceiptV3} from "rain-vats-0.1.6/src/interface/IReceiptV3.sol";

import {IST0xOrchestratorV1, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title BurnInfoAuditTrailTest
/// @notice Workflow: mint, hand the shares back, then burn with a NON-EMPTY
/// `burnInfo` and pin the audit trail end-to-end against the real vault:
/// `burnInfo` must arrive verbatim in the vault's `Withdraw` event and in the
/// receipt's `ReceiptInformation` event (the receipt only emits it at all
/// when the payload is non-empty, so a dropped payload silences the event).
contract BurnInfoAuditTrailTest is OrchestratorIntegrationTest {
    function testBurnInfoForwardedToVaultRedeem() external {
        (address eoa, uint256 pk) = makeAddrAndKey("audit-recipient");
        uint256 amount = 7e18;
        bytes32 nonce = keccak256("audit-burn");
        bytes memory burnInfo = bytes("st0x:debt-repay-burn:42");

        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "");
        uint256 mintedId = vault.highwaterId();

        vm.prank(eoa);
        assertTrue(IERC20(address(vault)).transfer(MM, amount), "hand shares to the burner");
        vm.prank(MM);
        IERC20(address(vault)).approve(address(orchestrator), amount);

        // The redeem inside the burn walk must carry `burnInfo` verbatim:
        // vault-side Withdraw first, then the receipt's ReceiptInformation
        // emitted by managerBurn, then the orchestrator's own Burned.
        vm.expectEmit(true, true, true, true, address(vault));
        emit IReceiptVaultV1.Withdraw(
            address(orchestrator), address(orchestrator), address(orchestrator), amount, amount, mintedId, burnInfo
        );
        vm.expectEmit(true, true, true, true, address(receipt));
        emit IReceiptV3.ReceiptInformation(address(orchestrator), mintedId, burnInfo);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Burned(MM, address(vault), amount, 0, mintedId + 1);
        vm.prank(MM);
        orchestrator.burn(address(vault), amount, burnInfo);

        assertEq(receipt.balanceOf(address(orchestrator), mintedId), 0, "receipt consumed");
        assertEq(vault.totalSupply(), 0, "supply fully unwound");
    }
}
