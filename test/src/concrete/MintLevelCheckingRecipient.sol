// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xOrchestratorV2, Digest} from "../../../src/interface/IST0xOrchestratorV2.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.10/src/lib/LibDecimalFloat.sol";

/// @dev Accepts a mint only if, at callback time, both its own recipient
/// bucket and `MINTER`'s bucket already hold `EXPECTED_LEVEL`.
contract MintLevelCheckingRecipient is IMintRecipient {
    using LibDecimalFloat for Float;

    IST0xOrchestratorV2 internal immutable ORCHESTRATOR;
    address internal immutable MINTER;
    Float internal immutable EXPECTED_LEVEL;

    constructor(IST0xOrchestratorV2 orchestrator, address minter, Float expectedLevel) {
        ORCHESTRATOR = orchestrator;
        MINTER = minter;
        EXPECTED_LEVEL = expectedLevel;
    }

    function authorizeMint(Digest) external view returns (bytes4) {
        bool charged = ORCHESTRATOR.recipientMintLevel(address(this)).eq(EXPECTED_LEVEL)
            && ORCHESTRATOR.minterMintLevel(MINTER).eq(EXPECTED_LEVEL);
        return charged ? IMintRecipient.authorizeMint.selector : bytes4(0xdeadbeef);
    }
}
