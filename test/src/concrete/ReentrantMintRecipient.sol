// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xOrchestratorV2, MintAuthV1, Digest} from "../../../src/interface/IST0xOrchestratorV2.sol";
import {SignedContextV2} from "rainlang-0.2.32/src/interface/IInterpreterCallerV5.sol";

/// @dev Malicious callback recipient: its `authorizeMint` reenters
/// `orchestrator.mint` to `REENTER_TO`, a different recipient, with a fresh
/// nonce and an empty signature. Any revert from the nested call bubbles up
/// unhandled. Requires `MINT_ROLE` and a minter limit for the nested call to
/// reach the guard.
contract ReentrantMintRecipient is IMintRecipient {
    IST0xOrchestratorV2 internal immutable ORCHESTRATOR;
    address internal immutable TOKEN;
    address internal immutable REENTER_TO;
    uint256 internal immutable REENTER_AMOUNT;
    bytes32 internal immutable REENTER_NONCE;

    // A test double storing the collaborator it is handed. Rejecting zero here
    // would only stop the suite exercising the zero case.
    constructor(
        IST0xOrchestratorV2 orchestrator,
        // forge-lint: disable-next-line(missing-zero-check)
        address token,
        // forge-lint: disable-next-line(missing-zero-check)
        address reenterTo,
        uint256 reenterAmount,
        bytes32 reenterNonce
    ) {
        ORCHESTRATOR = orchestrator;
        TOKEN = token;
        REENTER_TO = reenterTo;
        REENTER_AMOUNT = reenterAmount;
        REENTER_NONCE = reenterNonce;
    }

    function authorizeMint(Digest) external returns (bytes4) {
        ORCHESTRATOR.mint(
            TOKEN,
            REENTER_TO,
            REENTER_AMOUNT,
            MintAuthV1({nonce: REENTER_NONCE, signature: ""}),
            "",
            new SignedContextV2[](0)
        );
        return IMintRecipient.authorizeMint.selector;
    }
}
