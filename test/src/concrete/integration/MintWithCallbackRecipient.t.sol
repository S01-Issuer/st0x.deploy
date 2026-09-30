// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMintRecipient} from "../../../../src/interface/IMintRecipient.sol";
import {Digest} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";
import {AcceptingMintRecipient} from "./AcceptingMintRecipient.sol";
import {SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

/// @title MintWithCallbackRecipientTest
/// @notice Workflow: a contract recipient with no key authorises via the
/// `IMintRecipient.authorizeMint` callback (empty signature). The mint
/// completes and delivers shares to the contract.
contract MintWithCallbackRecipientTest is OrchestratorIntegrationTest {
    function testMintWithCallbackRecipient() external {
        AcceptingMintRecipient recipient = new AcceptingMintRecipient();
        _allowRecipient(address(recipient));
        uint256 amount = 42e18;
        bytes32 nonce = keccak256("callback");

        // The recipient is called with the mint's canonical EIP-712 digest.
        Digest digest = orchestrator.mintAuthDigest(address(vault), address(recipient), amount, nonce);
        vm.expectCall(address(recipient), abi.encodeWithSelector(IMintRecipient.authorizeMint.selector, digest));

        vm.prank(MM);
        orchestrator.mint(
            address(vault), address(recipient), amount, _callbackMintAuth(nonce), "", new SignedContextV1[](0)
        );

        assertEq(vault.balanceOf(address(recipient)), amount, "callback recipient received the shares");
        assertEq(receipt.balanceOf(address(orchestrator), vault.highwaterId()), amount, "orchestrator holds receipt");
    }
}
