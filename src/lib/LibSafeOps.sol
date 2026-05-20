// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {IGnosisSafe} from "../interface/IGnosisSafe.sol";

/// @notice The parsed Tx Builder JSON has zero transactions. Empty bundles
/// are never produced by `emitTxBuilderJson` and so a zero-length
/// `transactions` array is treated as an invariant break rather than a
/// no-op.
error TxBuilderJsonNoTransactions();

/// @notice A single Safe-Tx Builder transaction in canonical form. Mirrors
/// the per-transaction shape of the Safe Tx Builder JSON.
/// @param to The destination address of the inner transaction.
/// @param value The native value forwarded to `to`.
/// @param data The calldata forwarded to `to`. Self-mutating Safe calls
/// (e.g. `changeThreshold`) encode the inner call here and target the Safe
/// itself.
/// @param operation The Safe `Operation` enum: `0` for `CALL`, `1` for
/// `DELEGATECALL`.
struct SafeTx {
    address to;
    uint256 value;
    bytes data;
    uint8 operation;
}

/// @title LibSafeOps
/// @notice Off-chain Safe transaction helpers shared between the RAI-296
/// migration script and its tests. Wraps the canonical `getTransactionHash`
/// view, foundry-level simulation of self-calls and external calls, and the
/// Safe Tx Builder JSON serialise/parse round-trip used to hand the bundle
/// to signers via the Safe UI.
/// @dev The library is `Vm`-aware: it pokes the foundry cheatcode address
/// directly so callers can use it from non-Test contracts (notably the
/// `MigrateMultisigThreshold` script). The JSON helpers hand-assemble the
/// output rather than going through `vm.serializeJson` because the Tx
/// Builder schema requires `transactions` to be a JSON array of objects —
/// `vm.serializeString` keyed by index emits an object, not an array.
library LibSafeOps {
    /// @notice Reference to the foundry HEVM cheatcode address. Computed
    /// the same way `forge-std` computes its own `vm` reference, but here
    /// captured at library scope so non-Test callers (the script) can use
    /// the simulation/JSON helpers without inheriting `Test`.
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Safe Tx Builder version stamped into the `meta` block of
    /// emitted JSON bundles. Currently pinned at `"1.16.5"` to match the
    /// version produced by the public Safe Tx Builder app at the time of
    /// RAI-296 tooling authorship.
    string internal constant TX_BUILDER_VERSION = "1.16.5";

    /// @notice Tx Builder JSON schema version stamped into the top-level
    /// `version` field. Pinned at `"1.0"` (the only version the public Tx
    /// Builder UI currently accepts as of RAI-296 authorship).
    string internal constant TX_BUILDER_SCHEMA_VERSION = "1.0";

    /// @notice Wrapper around `getTransactionHash` on the live Safe.
    /// Binds the hash to the Safe's own EIP-712 domain separator (chain id,
    /// verifying contract) rather than recomputing it locally, so the
    /// off-chain artifact and on-chain verification can't drift apart. The
    /// inner-tx gas parameters are zeroed because the migration bundle does
    /// not request a refund and the Safe Tx Builder defaults the same way.
    /// @param safe The Safe whose nonce/domain are bound into the hash.
    /// @param txn The transaction to be hashed.
    /// @param nonce The Safe nonce the transaction will consume on execute.
    /// @return The canonical Safe transaction hash that owners must sign.
    function computeSafeTxHashViaSafe(IGnosisSafe safe, SafeTx memory txn, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        return safe.getTransactionHash(
            txn.to,
            txn.value,
            txn.data,
            txn.operation,
            // safeTxGas, baseGas, gasPrice, gasToken, refundReceiver: all
            // zero. The Safe Tx Builder defaults to the same values for
            // bundles built via its UI.
            0,
            0,
            0,
            address(0),
            address(0),
            nonce
        );
    }

    /// @notice Simulate a Safe self-call: `vm.prank` as the Safe itself and
    /// invoke the supplied calldata on the Safe address. Mirrors what the
    /// inner `execTransaction` path does after signature verification, so
    /// post-state assertions (threshold, owners, etc.) made against the
    /// fork after this call reflect the on-chain post-exec state.
    /// @dev The Safe's nonce is NOT advanced by this simulation — only
    /// `execTransaction` advances the nonce, and we explicitly do not
    /// invoke it because the goal is to assert the state the inner call
    /// produces, not to model the wrapping exec.
    /// @param safe The Safe to prank-call as.
    /// @param data The calldata to forward to the Safe.
    function simulateSelfCall(IGnosisSafe safe, bytes memory data) internal {
        address safeAddr = address(safe);
        VM.prank(safeAddr);
        // The returndata is intentionally discarded: callers assert against
        // post-state, not the inner return. If the inner call reverts we
        // bubble the reason rather than swallowing a low-level failure.
        // slither-disable-next-line low-level-calls
        (bool ok, bytes memory ret) = safeAddr.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    /// @notice Simulate a Safe-originated external call: `vm.prank` as the
    /// Safe and invoke `data` against `target`. Used when a bundle has the
    /// Safe call out to a non-self address (e.g. taking ownership of a
    /// dependency) so the same post-state assertions apply.
    /// @param safe The Safe to prank-call as.
    /// @param target The destination of the prank call.
    /// @param data The calldata to forward to `target`.
    function simulateExternalCall(IGnosisSafe safe, address target, bytes memory data) internal {
        VM.prank(address(safe));
        // slither-disable-next-line low-level-calls
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    /// @notice Serialise a Safe Tx Builder JSON bundle from the supplied
    /// inputs. The shape matches the Safe Tx Builder app's import format so
    /// the artifact can be loaded directly into the Safe UI for signing.
    /// @dev Field set:
    /// - `version`: pinned at `TX_BUILDER_SCHEMA_VERSION` (`"1.0"`).
    /// - `chainId`: the EVM chain id the bundle is scoped to (as a
    ///   decimal string — Tx Builder schema uses string-form chain ids).
    /// - `createdAt`: `block.timestamp` of the producing run (number).
    /// - `meta.name`: the human-readable bundle name (passed through).
    /// - `meta.txBuilderVersion`: pinned at `TX_BUILDER_VERSION`.
    /// - `meta.safeAddress`: echoes `safeAddr` so the bundle records
    ///   which Safe it was authored against. The Tx Builder UI ignores
    ///   unknown `meta` fields, so this is a forward-compatible pin.
    /// - `transactions`: array of per-tx objects `{to, value, data}`.
    /// `value` is serialised as a decimal string to match the Tx Builder
    /// schema.
    ///
    /// Output is hand-assembled with `string.concat` rather than
    /// `vm.serializeJson` because the cheatcode emits index-keyed objects
    /// for arrays, which the Tx Builder schema does not accept.
    /// @param safeAddr The Safe address the bundle targets. Echoed under
    /// `meta.safeAddress` so a parsed bundle can be cross-checked against
    /// the Safe an audit thinks it belongs to.
    /// @param chainId The chain id the bundle is scoped to.
    /// @param name The bundle name to embed in `meta.name`.
    /// @param txs The transactions to serialise.
    /// @return The serialised JSON string.
    function emitTxBuilderJson(address safeAddr, uint256 chainId, string memory name, SafeTx[] memory txs)
        internal
        view
        returns (string memory)
    {
        string memory transactions = "[";
        for (uint256 i = 0; i < txs.length; i++) {
            string memory txJson = string.concat(
                "{",
                _jsonField("to", _quote(VM.toString(txs[i].to))),
                ",",
                _jsonField("value", _quote(VM.toString(txs[i].value))),
                ",",
                _jsonField("data", _quote(VM.toString(txs[i].data))),
                "}"
            );
            transactions = string.concat(transactions, txJson);
            if (i + 1 < txs.length) {
                transactions = string.concat(transactions, ",");
            }
        }
        transactions = string.concat(transactions, "]");

        // Embed `safeAddr` under `meta.safeAddress` so the bundle records
        // the Safe it was authored against. The Tx Builder UI ignores
        // unknown `meta` fields, so this is a forward-compatible pin.
        string memory meta = string.concat(
            "{",
            _jsonField("name", _quote(name)),
            ",",
            _jsonField("txBuilderVersion", _quote(TX_BUILDER_VERSION)),
            ",",
            _jsonField("safeAddress", _quote(VM.toString(safeAddr))),
            "}"
        );

        return string.concat(
            "{",
            _jsonField("version", _quote(TX_BUILDER_SCHEMA_VERSION)),
            ",",
            _jsonField("chainId", _quote(VM.toString(chainId))),
            ",",
            _jsonField("createdAt", VM.toString(block.timestamp)),
            ",",
            _jsonField("meta", meta),
            ",",
            _jsonField("transactions", transactions),
            "}"
        );
    }

    /// @notice Parse a Safe Tx Builder JSON file from disk and return the
    /// chain id, target Safe, and transactions array.
    /// @dev The Tx Builder JSON's `transactions[*].value` is a decimal
    /// string and `data` is a `0x`-prefixed hex byte string. The first
    /// transaction's `to` is reported as the bundle's target Safe address
    /// because by Tx Builder convention every Safe-self-mutating bundle
    /// has every tx target the Safe itself; bundles with cross-target
    /// calls have to inspect the array directly.
    /// @param jsonPath Filesystem path to the JSON file.
    /// @return chainId The chain id parsed from the JSON.
    /// @return safeAddr The Safe address (parsed from `transactions[0].to`).
    /// @return txs The decoded transactions array.
    function parseTxBuilderJson(string memory jsonPath)
        internal
        view
        returns (uint256 chainId, address safeAddr, SafeTx[] memory txs)
    {
        string memory json = VM.readFile(jsonPath);
        chainId = _parseDecimalUint(VM.parseJsonString(json, ".chainId"));

        // The Tx Builder schema's `transactions` is an array of objects.
        // `parseJsonKeys` rejects arrays and `parseJsonAddressArray` with
        // a wildcard path mis-decodes a single match, so we discover the
        // array length by probing `.transactions[i]` via `keyExistsJson`
        // until the index is no longer present. The cap is a defensive
        // upper bound — RAI-296's migration bundle is single-tx, and the
        // Tx Builder UI itself imposes a far smaller practical limit.
        uint256 cap = 256;
        SafeTx[] memory scratch = new SafeTx[](cap);
        uint256 count = 0;
        for (uint256 i = 0; i < cap; i++) {
            string memory iStr = VM.toString(i);
            if (!VM.keyExistsJson(json, string.concat(".transactions[", iStr, "].to"))) {
                break;
            }
            address to = VM.parseJsonAddress(json, string.concat(".transactions[", iStr, "].to"));
            uint256 value =
                _parseDecimalUint(VM.parseJsonString(json, string.concat(".transactions[", iStr, "].value")));
            bytes memory data = VM.parseJsonBytes(json, string.concat(".transactions[", iStr, "].data"));
            scratch[count] = SafeTx({to: to, value: value, data: data, operation: 0});
            count++;
        }
        if (count == 0) {
            revert TxBuilderJsonNoTransactions();
        }
        txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            txs[i] = scratch[i];
        }
        safeAddr = txs[0].to;
    }

    /// @notice Parse a decimal-formatted unsigned integer string. The Tx
    /// Builder schema serialises `chainId` and `value` as decimal strings,
    /// so this is the inverse of `vm.toString(uint256)`.
    /// @param decimal The decimal-formatted string. Must contain only
    /// `0..9` digits; any non-digit reverts with a static message.
    /// @return The parsed unsigned integer.
    function _parseDecimalUint(string memory decimal) private pure returns (uint256) {
        bytes memory raw = bytes(decimal);
        uint256 result = 0;
        for (uint256 i = 0; i < raw.length; i++) {
            uint8 c = uint8(raw[i]);
            // ASCII digits run `0x30..0x39`.
            require(c >= 0x30 && c <= 0x39, "LibSafeOps: non-decimal digit");
            result = result * 10 + (c - 0x30);
        }
        return result;
    }

    /// @notice Helper: emit a JSON `"key": value` field. The value must
    /// already be a serialised JSON literal (quoted string, number, or
    /// object); use `_quote` to wrap raw strings.
    /// @param key The JSON object key.
    /// @param valueLiteral The serialised JSON value.
    /// @return The serialised `"key":value` fragment.
    function _jsonField(string memory key, string memory valueLiteral) private pure returns (string memory) {
        return string.concat('"', key, '":', valueLiteral);
    }

    /// @notice Helper: wrap a raw string in JSON-quote delimiters. Does not
    /// escape inner quotes/control characters — callers in this library
    /// pass values from `vm.toString` (which never emits a quote) or
    /// hard-coded literals, so the simpler implementation suffices.
    /// @param raw The raw string.
    /// @return The quoted JSON string literal.
    function _quote(string memory raw) private pure returns (string memory) {
        return string.concat('"', raw, '"');
    }
}
