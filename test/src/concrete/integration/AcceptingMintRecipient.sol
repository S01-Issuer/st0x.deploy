// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMintRecipient} from "../../../../src/interface/IMintRecipient.sol";
import {Digest} from "../../../../src/interface/IST0xOrchestratorV1.sol";

/// @dev Contract recipient that authorises any mint via the `IMintRecipient`
/// callback (accepts unconditionally). Holds the shares it is minted.
contract AcceptingMintRecipient is IMintRecipient {
    function authorizeMint(Digest) external pure returns (bytes4) {
        return IMintRecipient.authorizeMint.selector;
    }
}
