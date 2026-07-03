// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Digest} from "./IST0xOrchestratorV1.sol";

/// @title IMintRecipient
/// @notice Callback interface a contract recipient implements to authorise an
/// orchestrator mint of shares to itself, as an alternative to providing an
/// EIP-712 signature. Modelled on the ERC-1155 receiver acceptance pattern:
/// the orchestrator calls `authorizeMint` with the mint's canonical digest
/// and only proceeds if the recipient returns the function selector.
///
/// This lets a contract that cannot hold a private key (e.g. the atomic
/// bridge) gate mints on its own on-chain intent — it records the expected
/// mint, then returns the selector only for a digest it is expecting.
///
/// `Digest` is an aliased `bytes32`, so the ABI (and this function's
/// selector) is identical to `authorizeMint(bytes32)`.
interface IMintRecipient {
    /// @notice Authorise a mint of shares to this contract.
    /// @param digest The orchestrator's EIP-712 digest binding
    /// `(token, recipient, amount, nonce)`. The recipient should verify it
    /// matches an intent it recorded and has not already consumed.
    /// @return The `authorizeMint.selector` magic value if authorised; any
    /// other value (or a revert) rejects the mint.
    function authorizeMint(Digest digest) external returns (bytes4);
}
