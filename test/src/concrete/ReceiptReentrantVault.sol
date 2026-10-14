// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IST0xOrchestratorV1, MintAuthV1} from "../../../src/interface/IST0xOrchestratorV1.sol";

/// @dev Vault logic whose `receipt()` reenters the orchestrator from inside
/// the vault-logic lock and bubbles the nested revert.
contract ReceiptReentrantVault {
    IST0xOrchestratorV1 public immutable ORCHESTRATOR;
    bool public immutable REENTER_MINT;

    constructor(IST0xOrchestratorV1 orchestrator, bool reenterMint) {
        ORCHESTRATOR = orchestrator;
        REENTER_MINT = reenterMint;
    }

    function receipt() external returns (address) {
        bytes memory data = REENTER_MINT
            ? abi.encodeCall(
                IST0xOrchestratorV1.mint,
                (address(this), address(this), 1, MintAuthV1({nonce: bytes32(0), signature: ""}), "")
            )
            : abi.encodeCall(IST0xOrchestratorV1.burn, (address(this), 1, ""));
        (bool ok, bytes memory ret) = address(ORCHESTRATOR).call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        return address(this);
    }
}
