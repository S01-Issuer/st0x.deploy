// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IGnosisSafe
/// @notice Minimal interface for interacting with a Safe (formerly Gnosis Safe)
/// proxy. Pinned at the surface required by the multisig threshold migration
/// tooling: read-only owner/threshold/version/storage introspection, the
/// canonical transaction hash builder, and the privileged `changeThreshold`
/// mutator (self-call only — guarded by the Safe's own signature verification
/// in production; reachable in tests via `vm.prank`).
/// @dev This interface intentionally omits the rest of the Safe ABI (sigs,
/// owner management, module management, fallback handler config, etc.) — the
/// migration tooling only needs the functions declared here. Extending this
/// interface in future migrations is preferred over re-declaring functions
/// locally per script.
///
/// All function signatures match the canonical Safe v1.4.1 L2 source:
/// https://github.com/safe-global/safe-contracts/tree/v1.4.1/contracts
interface IGnosisSafe {
    /// @notice Allows the Safe (self-call only) to update the number of owner
    /// signatures required to confirm a transaction.
    /// @param threshold The new threshold. Must be `> 0` and `<= owners.length`
    /// as enforced by the Safe's OwnerManager. Reverts otherwise.
    function changeThreshold(uint256 threshold) external;

    /// @notice Returns the current signature threshold.
    /// @return The number of owner signatures required to execute a transaction.
    function getThreshold() external view returns (uint256);

    /// @notice Returns the current owner set in Safe-internal linked-list
    /// order (sentinel is `address(0x1)`).
    /// @return The list of owner addresses for this Safe.
    function getOwners() external view returns (address[] memory);

    /// @notice Returns the current Safe transaction nonce. Used as the `_nonce`
    /// argument to `getTransactionHash` when computing the next executable
    /// transaction's hash off-chain.
    /// @return The next nonce that will be consumed by `execTransaction`.
    function nonce() external view returns (uint256);

    /// @notice Paginated module enumeration. Walks the modules linked list
    /// starting from `start` (use sentinel `address(0x1)` to enumerate from
    /// the head).
    /// @param start The cursor address. Pass `address(0x1)` to begin at the
    /// head of the modules linked list.
    /// @param pageSize The maximum number of modules to return in this call.
    /// @return array The modules page (length up to `pageSize`).
    /// @return next The next cursor address. Equal to `start` (sentinel) when
    /// the list is empty, or a module address to feed back into a subsequent
    /// call when paging is incomplete.
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);

    /// @notice Computes the canonical EIP-712 transaction hash for the supplied
    /// transaction inputs. This is the hash that owners must sign for
    /// `execTransaction` to accept the bundle.
    /// @dev We delegate hashing to the live Safe instance rather than
    /// recomputing locally — this binds the produced hash to the Safe's
    /// declared domain separator and prevents drift between off-chain tooling
    /// and on-chain verification.
    /// @param to Destination of the inner transaction.
    /// @param value Native value forwarded to `to`.
    /// @param data Calldata forwarded to `to`.
    /// @param operation `0` for `CALL`, `1` for `DELEGATECALL`.
    /// @param safeTxGas Gas forwarded to the inner call.
    /// @param baseGas Fixed gas costs added on top of `safeTxGas` for refund.
    /// @param gasPrice Refund gas price (zero for non-refunded executions).
    /// @param gasToken Token used for the refund (zero address for native).
    /// @param refundReceiver Refund receiver (zero address for `tx.origin`).
    /// @param _nonce Safe nonce that this transaction will consume.
    /// @return The Safe transaction hash.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);

    /// @notice Reads raw storage from the Safe proxy. Used to assert
    /// well-known Safe storage slots (singleton, fallback handler, guard)
    /// without going through accessor functions that could be shadowed by a
    /// malicious fallback.
    /// @param offset Starting storage slot index.
    /// @param length Number of slots to read.
    /// @return The concatenated 32-byte words read from storage.
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);

    /// @notice Returns the Safe implementation's version string. For Safe
    /// v1.4.1 the canonical value is `"1.4.1"`.
    /// @return The version string declared by the Safe singleton.
    /// @dev `VERSION` is upper-case to match the canonical Safe ABI selector;
    /// renaming would break ABI compatibility with the live deployment.
    //slither-disable-next-line naming-convention
    function VERSION() external view returns (string memory);

    /// @notice Marks the supplied Safe transaction hash as pre-approved by
    /// `msg.sender`. Subsequent `execTransaction` calls can satisfy
    /// `checkSignatures` for this hash by supplying a `v=1` signature entry
    /// whose `r` field is `bytes32(uint256(uint160(msg.sender)))` instead of
    /// an ECDSA tuple.
    /// @dev Only callable by an owner of the Safe. Used by the reversibility
    /// helper in `LibSafeOps` to satisfy signature verification under a
    /// `vm.prank` without requiring test private keys for owner addresses.
    /// @param hashToApprove The Safe transaction hash to pre-approve.
    function approveHash(bytes32 hashToApprove) external;

    /// @notice Executes a Safe transaction. Signature verification routes
    /// through `checkSignatures`, which accepts both ECDSA signatures and
    /// the `v=1` pre-approved-hash variant produced by `approveHash`.
    /// @dev The Safe v1.4.1 source asserts the packed `signatures` blob is
    /// sorted ascending by signer address and contains at least `threshold`
    /// entries (`GS020`: "Signatures data too short" when too few).
    /// @param to Destination of the inner transaction.
    /// @param value Native value forwarded to `to`.
    /// @param data Calldata forwarded to `to`.
    /// @param operation `0` for `CALL`, `1` for `DELEGATECALL`.
    /// @param safeTxGas Gas forwarded to the inner call.
    /// @param baseGas Fixed gas costs added on top of `safeTxGas` for refund.
    /// @param gasPrice Refund gas price (zero for non-refunded executions).
    /// @param gasToken Token used for the refund (zero address for native).
    /// @param refundReceiver Refund receiver (zero address for `tx.origin`).
    /// @param signatures Packed owner signatures, ordered ascending by
    /// signer address. Each entry is 65 bytes (`r || s || v`); the `v=1`
    /// variant treats `r` as a pre-approver address.
    /// @return success Whether the inner call succeeded after signature
    /// verification.
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool success);
}
