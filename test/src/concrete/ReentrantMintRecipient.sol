// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xOrchestratorV1, MintAuthV1, Digest} from "../../../src/interface/IST0xOrchestratorV1.sol";

/// @dev Malicious callback recipient: on the first `authorizeMint` it
/// reenters `orchestrator.mint` for itself with a fresh nonce (empty
/// signature, so the nested mint authorises via this same callback, which
/// accepts on the second entry). Any revert from the nested call bubbles up
/// unhandled, so with the reentrancy guard in place the outer mint reverts
/// `ReentrancyGuardReentrantCall`. Requires `MINT_ROLE` for the nested call
/// to reach the guard.
contract ReentrantMintRecipient is IMintRecipient {
    IST0xOrchestratorV1 internal immutable ORCHESTRATOR;
    address internal immutable TOKEN;
    uint256 internal immutable REENTER_AMOUNT;
    bytes32 internal immutable REENTER_NONCE;

    bool public entered;

    constructor(IST0xOrchestratorV1 orchestrator, address token, uint256 reenterAmount, bytes32 reenterNonce) {
        ORCHESTRATOR = orchestrator;
        TOKEN = token;
        REENTER_AMOUNT = reenterAmount;
        REENTER_NONCE = reenterNonce;
    }

    function authorizeMint(Digest) external returns (bytes4) {
        if (!entered) {
            entered = true;
            ORCHESTRATOR.mint(
                TOKEN, address(this), REENTER_AMOUNT, MintAuthV1({nonce: REENTER_NONCE, signature: ""}), ""
            );
        }
        return IMintRecipient.authorizeMint.selector;
    }
}
