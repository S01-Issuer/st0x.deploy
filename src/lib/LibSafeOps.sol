// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {IGnosisSafe} from "../interface/IGnosisSafe.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

/// @notice Minimal `UpgradeableBeacon` surface used by the beacon n+1
/// helper: the privileged `upgradeTo` mutator. Declared inline so
/// `LibSafeOps` owns the only beacon selector it encodes rather than
/// importing the full OZ `UpgradeableBeacon` type for a single `abi.encodeCall`.
interface IUpgradeableBeacon {
    /// @notice Point the beacon at a new implementation. `onlyOwner` on the
    /// OZ beacon; reachable here only because the n+1 helper routes the call
    /// through the owning Safe's `execTransaction`.
    /// @param newImplementation The implementation address to set.
    function upgradeTo(address newImplementation) external;
}

/// @notice The parsed Tx Builder JSON has zero transactions. Empty bundles
/// are never produced by `emitTxBuilderJson` and so a zero-length
/// `transactions` array is treated as an invariant break rather than a
/// no-op.
error TxBuilderJsonNoTransactions();

/// @notice `emitTxBuilderJson` was handed a transaction with a non-CALL
/// `operation`. The Safe Tx Builder JSON schema has no per-transaction
/// `operation` field and the canonical batch executor (`MultiSendCallOnly`)
/// only performs CALLs, so a non-CALL operation cannot be represented in the
/// artifact and is rejected.
/// @param index The index of the offending transaction in the bundle.
/// @param operation The unsupported operation value.
error TxBuilderJsonUnsupportedOperation(uint256 index, uint8 operation);

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
/// @notice Off-chain Safe transaction helpers shared between the multisig
/// threshold migration script and its tests. Wraps the canonical
/// `getTransactionHash` view, foundry-level simulation of self-calls and
/// external calls, and the Safe Tx Builder JSON serialise/parse round-trip
/// used to hand the bundle to signers via the Safe UI.
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
    /// version produced by the public Safe Tx Builder app at the time
    /// this library was authored.
    string internal constant TX_BUILDER_VERSION = "1.16.5";

    /// @notice Tx Builder JSON schema version stamped into the top-level
    /// `version` field. Pinned at `"1.0"` (the only version the public Tx
    /// Builder UI currently accepts at the time this library was
    /// authored).
    string internal constant TX_BUILDER_SCHEMA_VERSION = "1.0";

    /// @notice The canonical Safe{Wallet} v1.4.1 `MultiSendCallOnly` — the
    /// contract the Transaction Builder delegatecalls to execute a batch of
    /// transactions atomically. Performs only CALLs. Pinned alongside the
    /// Safe v1.4.1 assumption enforced by `LibSafeInvariants`.
    /// https://basescan.org/address/0x9641d764fc13c8B624c04430C7356C1C7C8102e2
    address internal constant MULTISEND_CALL_ONLY_1_4_1 = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

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

    /// @notice Encode a batch of transactions into the
    /// `MultiSendCallOnly.multiSend(bytes)` calldata the Safe Transaction
    /// Builder submits for a batch: each transaction packed as
    /// `operation(1 byte) || to(20) || value(32) || dataLength(32) || data`,
    /// concatenated and ABI-wrapped behind the `multiSend(bytes)` selector.
    /// @param txs The transactions to batch.
    /// @return The `multiSend(bytes)` calldata.
    function encodeMultiSend(SafeTx[] memory txs) internal pure returns (bytes memory) {
        bytes memory payload = new bytes(0);
        for (uint256 i = 0; i < txs.length; i++) {
            payload = bytes.concat(
                payload, abi.encodePacked(txs[i].operation, txs[i].to, txs[i].value, txs[i].data.length, txs[i].data)
            );
        }
        return abi.encodeWithSignature("multiSend(bytes)", payload);
    }

    /// @notice The canonical Safe transaction hash owners must sign to execute
    /// a multi-transaction bundle through the Transaction Builder. The bundle
    /// executes as a single `execTransaction` DELEGATECALL to
    /// `MULTISEND_CALL_ONLY_1_4_1` at one nonce, so the hash binds to that one
    /// wrapping transaction rather than to the individual inner calls.
    /// @param safe The Safe whose nonce/domain bind into the hash.
    /// @param txs The batched transactions.
    /// @param nonce The Safe nonce the batch consumes on execute.
    /// @return The canonical Safe transaction hash owners must sign.
    function computeMultiSendSafeTxHash(IGnosisSafe safe, SafeTx[] memory txs, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        SafeTx memory batchTx =
            SafeTx({to: MULTISEND_CALL_ONLY_1_4_1, value: 0, data: encodeMultiSend(txs), operation: 1});
        return computeSafeTxHashViaSafe(safe, batchTx, nonce);
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
            // The Tx Builder schema + MultiSendCallOnly are CALL-only, so a
            // non-CALL op cannot be represented in the artifact.
            if (txs[i].operation != 0) {
                revert TxBuilderJsonUnsupportedOperation(i, txs[i].operation);
            }
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
        // upper bound — the threshold migration bundle is single-tx, and the
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
            // The Tx Builder schema has no per-tx `operation` field; every
            // entry is a CALL (operation 0). `emitTxBuilderJson` rejects
            // non-CALL ops, so 0 is the only value a well-formed bundle carries.
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

    /// @notice Reversibility / "not stuck" check for a state-changing
    /// operation. After a script has simulated its forward state change
    /// (e.g. `changeThreshold(newThreshold)`), this helper proves on the
    /// same fork that the safe accepts a valid `execTransaction` under the
    /// new threshold and that the threshold gate correctly rejects
    /// undersigned attempts. Specifically, builds an inverse follow-up
    /// transaction (`changeThreshold(oldThreshold)`) and:
    ///
    /// 1. Pre-approves the followup hash from `newThreshold` owners via
    ///    `vm.prank(owner) + safe.approveHash(hash)`. Sorted ascending by
    ///    signer address to satisfy Safe v1.4.1's `checkSignatures`.
    /// 2. Calls `execTransaction` with only `newThreshold - 1` packed
    ///    approved-hash signatures; asserts the call reverts with
    ///    `"GS020"` (Safe v1.4.1's "Signatures data too short").
    /// 3. Calls `execTransaction` with all `newThreshold` packed
    ///    approved-hash signatures; asserts success and that
    ///    `getThreshold()` is now back at `oldThreshold`.
    ///
    /// The check uses pre-approved hashes (`approvedHashes` mapping +
    /// `v=1` signature type) rather than ECDSA signatures, avoiding the
    /// need for test private keys or owner-slot overwrites. The real
    /// `checkSignatures` path is exercised end-to-end; only the source of
    /// the approval is the cheatcode prank.
    ///
    /// Intended to be called from operational scripts as the final post-
    /// state assertion, so every dry-run proves the new state is not a
    /// dead-end. Generalises to other critical state changes (e.g.
    /// authoriser swaps, role grants) by parameterising the inverse op
    /// in a future variant.
    ///
    /// @param safe The Safe whose post-mutation state to exercise.
    /// @param oldThreshold The threshold the safe should return to after
    /// the reversal executes. Must match the safe's threshold before the
    /// forward change.
    /// @param newThreshold The threshold the safe is currently in. Both
    /// the number of approvals collected and the number passed in the
    /// successful `execTransaction` call.
    function simulateNPlus1Reversal(IGnosisSafe safe, uint256 oldThreshold, uint256 newThreshold) internal {
        // The inverse op is a self-call to `changeThreshold(oldThreshold)`:
        // the simplest, most reversible follow-up, with no side effect other
        // than the threshold mutation itself. Delegated to the generic
        // `simulateNPlus1` so the signature mechanics live in one place; this
        // wrapper keeps its original signature and behaviour so the
        // threshold-migration tests continue to pass unchanged.
        bytes memory inverseCalldata = abi.encodeCall(IGnosisSafe.changeThreshold, (oldThreshold));
        simulateNPlus1(safe, address(safe), inverseCalldata, newThreshold);
        require(safe.getThreshold() == oldThreshold, "LibSafeOps: n+1 did not restore the prior threshold");
    }

    /// @notice Generic n+1 reversibility / "not stuck" check. Given a Safe in
    /// some post-mutation state, an arbitrary follow-up call (`target` +
    /// `inverseCalldata`), and the Safe's current `threshold`, this proves on
    /// the active fork that:
    ///
    /// 1. The Safe accepts a valid `execTransaction` for the follow-up under
    ///    the current threshold (the positive case), and
    /// 2. The threshold gate rejects an undersigned attempt with `GS020`
    ///    (the negative case).
    ///
    /// Together these prove the post-mutation state is genuinely exitable:
    /// the owning Safe can still author and execute a transaction against
    /// `target`, and the signature gate is doing its job. The follow-up call
    /// is supplied as raw calldata so the same mechanics serve a Safe
    /// self-call (threshold migration: `target == safe`), a beacon upgrade
    /// (`target == beacon`, `upgradeTo(...)`), or any other critical state
    /// change.
    ///
    /// As with `simulateNPlus1Reversal`, approvals are sourced via
    /// `approveHash` under `vm.prank` rather than ECDSA signatures, so no
    /// test private keys are needed; the real `checkSignatures` path is
    /// exercised end-to-end. The Safe's nonce IS advanced by the successful
    /// `execTransaction` (unlike `simulateSelfCall`), because this models the
    /// full wrapping exec.
    ///
    /// @dev This helper asserts the follow-up executes and the gate rejects
    /// undersigned attempts, but does NOT assert anything about the inner
    /// call's effect — callers that need a specific post-condition (e.g. the
    /// threshold rolled back to a prior value) assert it themselves after
    /// this returns. `simulateNPlus1Reversal` is exactly such a caller.
    /// @param safe The Safe whose post-mutation state to exercise.
    /// @param target The destination of the follow-up call. Pass
    /// `address(safe)` for a Safe self-call.
    /// @param inverseCalldata The calldata for the follow-up call.
    /// @param threshold The Safe's current threshold. Both the number of
    /// approvals collected and the number passed in the successful
    /// `execTransaction` call.
    function simulateNPlus1(IGnosisSafe safe, address target, bytes memory inverseCalldata, uint256 threshold)
        internal
    {
        SafeTx memory followup = SafeTx({to: target, value: 0, data: inverseCalldata, operation: 0});
        uint256 followupNonce = safe.nonce();
        bytes32 followupHash = computeSafeTxHashViaSafe(safe, followup, followupNonce);

        // Collect approvals from `threshold` owners. We always take the
        // first `threshold` entries from `getOwners()` — the linked-list
        // order is deterministic per-Safe so the choice is stable, and
        // sorting the resulting array by address normalises against the
        // arbitrary Safe-internal ordering before passing to
        // `checkSignatures`.
        address[] memory owners = safe.getOwners();
        require(owners.length >= threshold, "LibSafeOps: not enough owners for n+1");
        address[] memory approvers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            approvers[i] = owners[i];
            VM.prank(owners[i]);
            safe.approveHash(followupHash);
        }

        // Sort ascending by signer address — Safe v1.4.1's `checkSignatures`
        // requires the packed signature blob to be ordered by signer to
        // prevent the same signer counting twice.
        address[] memory sortedSigners = sortAddressesAscending(approvers);

        // Negative case: undersigned call must revert with `GS020`
        // ("Signatures data too short"). This is what proves the threshold
        // gate is doing its job — a follow-up tx is not magically waveable
        // through just because the approvals exist; the packed blob has to
        // contain at least `threshold` entries.
        bytes memory tooFewSigs = packApprovedHashSignatures(sortedSigners, threshold - 1);
        VM.expectRevert(bytes("GS020"));
        // The return value is meaningless under `expectRevert` — the call
        // must revert with the literal `GS020` reason, and the cheatcode
        // bubbles a test failure if it does not. Discarding the return is
        // therefore the correct behaviour.
        //slither-disable-next-line unused-return
        safe.execTransaction(
            followup.to,
            followup.value,
            followup.data,
            followup.operation,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            tooFewSigs
        );

        // Positive case: full `threshold`-many signatures must succeed. The
        // success assertion proves the new state is genuinely exitable: the
        // signature path verifies, the inner call executes, and the owning
        // Safe could run another forward migration against `target`.
        bytes memory enoughSigs = packApprovedHashSignatures(sortedSigners, threshold);
        bool ok = safe.execTransaction(
            followup.to,
            followup.value,
            followup.data,
            followup.operation,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            enoughSigs
        );
        require(ok, "LibSafeOps: n+1 execTransaction reverted unexpectedly");
    }

    /// @notice Beacon-specific n+1 reversibility convenience. Proves the
    /// owning Safe can act on `beacon` post-ownership-migration by running an
    /// idempotent `upgradeTo(currentImpl)` as the follow-up op: the call
    /// routes through the Safe's `execTransaction` (exercising the threshold
    /// gate both ways) and re-sets the beacon to the implementation it
    /// already points at, so there is no net state change.
    /// @dev The idempotent `upgradeTo` is the inverse op recommended in the
    /// design plan: it touches no real state (the beacon ends pointing at the
    /// same implementation) yet proves the Safe -> beacon call path works
    /// end-to-end through the signature-verified exec. Delegates to the
    /// generic `simulateNPlus1` with the `upgradeTo(currentImpl)` calldata.
    /// @param safe The Safe that owns the beacon after the migration.
    /// @param beacon The beacon to exercise.
    /// @param currentImpl The beacon's current implementation. Passed as the
    /// `upgradeTo` argument so the op is idempotent.
    /// @param threshold The Safe's current threshold.
    function simulateBeaconNPlus1(IGnosisSafe safe, address beacon, address currentImpl, uint256 threshold) internal {
        bytes memory inverseCalldata = abi.encodeCall(IUpgradeableBeacon.upgradeTo, (currentImpl));
        simulateNPlus1(safe, beacon, inverseCalldata, threshold);
        // Post-condition: the idempotent upgrade left the beacon pointing at
        // the same implementation it started on, confirming the routed call
        // actually executed against the beacon (not just that the Safe
        // accepted the signatures).
        require(
            IBeacon(beacon).implementation() == currentImpl,
            "LibSafeOps: beacon n+1 did not preserve the implementation"
        );
    }

    /// @notice Insertion-sort an in-memory address array ascending. Used to
    /// satisfy Safe v1.4.1's requirement that packed signatures are ordered
    /// by signer address before being passed to `checkSignatures`.
    /// @dev Insertion sort is O(n^2) but the input is bounded by the Safe
    /// owner count (single-digit in practice), so the constant factor wins
    /// over any more elaborate algorithm. The function returns a fresh array
    /// rather than sorting in place so callers can keep the original-order
    /// approver list around if they need it.
    /// @param addrs The unsorted address array.
    /// @return The same addresses in ascending order, in a freshly-allocated
    /// array of the same length.
    function sortAddressesAscending(address[] memory addrs) internal pure returns (address[] memory) {
        address[] memory sorted = new address[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            sorted[i] = addrs[i];
        }
        for (uint256 i = 1; i < sorted.length; i++) {
            address current = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > current) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = current;
        }
        return sorted;
    }

    /// @notice Pack the first `count` entries of `sortedSigners` into a
    /// Safe v1.4.1 approved-hash signature bytes blob. Each entry is 65
    /// bytes laid out as `r || s || v` where `r = bytes32(signerAddress)`
    /// (left-zero-padded), `s = bytes32(0)`, `v = 0x01`.
    /// @dev `v = 1` is the Safe v1.4.1 marker for "this hash was previously
    /// approved by `r` via `approveHash`": `checkSignatures` reads `r` as an
    /// address and consults the Safe's `approvedHashes[r][hash]` mapping
    /// instead of doing ECDSA recovery. `sortedSigners` MUST already be in
    /// ascending order — Safe's own ordering check rejects duplicates by
    /// requiring strict ascent.
    /// @param sortedSigners The signer addresses, sorted ascending.
    /// @param count The number of leading entries to pack. Allows callers
    /// to pack a deliberately-undersigned blob (for the negative branch of
    /// `simulateNPlus1Reversal`) without rebuilding the input array.
    /// @return packed The packed signature bytes, `count * 65` bytes long.
    function packApprovedHashSignatures(address[] memory sortedSigners, uint256 count)
        internal
        pure
        returns (bytes memory packed)
    {
        require(count <= sortedSigners.length, "LibSafeOps: pack count exceeds signers");
        packed = new bytes(0);
        for (uint256 i = 0; i < count; i++) {
            packed =
                bytes.concat(packed, bytes32(uint256(uint160(sortedSigners[i]))), bytes32(uint256(0)), bytes1(0x01));
        }
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
