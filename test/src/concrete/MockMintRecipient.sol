// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {Digest} from "../../../src/interface/IST0xOrchestratorV1.sol";

/// @dev Callback recipient mock. Returns the `authorizeMint` selector when
/// `accept`, else a wrong value.
contract MockMintRecipient is IMintRecipient {
    bool internal immutable ACCEPT;

    constructor(bool accept) {
        ACCEPT = accept;
    }

    function authorizeMint(Digest) external view returns (bytes4) {
        return ACCEPT ? IMintRecipient.authorizeMint.selector : bytes4(0xdeadbeef);
    }
}
