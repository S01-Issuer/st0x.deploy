// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

/// @dev An EIP-712 typed-data digest produced by the orchestrator's
/// `mintAuthDigest`. Aliased so the compiler rejects any `bytes32` that was
/// not explicitly produced as a digest (and vice versa).
type Digest is bytes32;

/// @dev Versioned shape of a mint authorisation, produced by the RECIPIENT
/// of a mint (never the minter — the minter is responsible only for
/// `receiptInformation`). A future breaking change to this shape ships as
/// `MintAuthV2` alongside a new mint entrypoint, so callers break loudly at
/// the ABI rather than silently mis-decoding.
/// @param nonce Single-use per recipient: the orchestrator namespaces replay
/// protection by `(to, nonce)`, so a recipient's nonce can never be replayed
/// with a different token or amount, and no third party can consume another
/// recipient's nonce. Callers should generate random 32-byte nonces (or hash
/// an internal counter with their own address).
/// @param signature EIP-712 signature by `to` over the digest of
/// `(token, to, amount, nonce)` — ECDSA for EOAs, EIP-1271 for contracts.
/// Empty triggers the `IMintRecipient.authorizeMint` callback on `to`
/// instead.
struct MintAuthV1 {
    bytes32 nonce;
    bytes signature;
}

/// @title IST0xOrchestratorV1
/// @notice Full external interface of the ST0x orchestrator — the singleton
/// mint/burn proxy for the whole ST0x receipt-vault set. Import this (rather
/// than the concrete contract) to interact with the orchestrator from other
/// contracts.
interface IST0xOrchestratorV1 {
    event Minted(address indexed caller, address indexed token, address indexed to, uint256 amount, bytes32 nonce);
    /// @param firstReceiptId `nextBurnReceiptId[token]` at the start of the call.
    /// @param nextBurnReceiptIdAfter The pointer at the end of the call. The
    /// walk only ever moves forward within a burn, so `[firstReceiptId,
    /// nextBurnReceiptIdAfter)` is the consumed id range.
    event Burned(
        address indexed caller,
        address indexed token,
        uint256 amount,
        uint256 firstReceiptId,
        uint256 nextBurnReceiptIdAfter
    );
    /// @notice `EMERGENCY_ROLE` manually overrode `token`'s burn pointer.
    event BurnIndexSet(address indexed token, uint256 oldIndex, uint256 newIndex);
    /// @notice A production receipt arrived at an id below `token`'s burn
    /// pointer and the receiver hook lowered the pointer to it, so the
    /// transferred-in receipt is burnable without manual intervention.
    event BurnIndexLowered(address indexed token, uint256 oldIndex, uint256 newIndex);
    event ReceiptsWithdrawn(address indexed token, address indexed to, uint256 indexed id, uint256 amount);
    event SharesWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice A foreign ERC-1155 (not a production receipt) was swept out via
    /// `sweepERC1155`. Distinct from `ReceiptsWithdrawn` so indexers never
    /// mistake `erc1155` for a receipt-vault address.
    event ForeignERC1155Swept(address indexed erc1155, address indexed to, uint256 indexed id, uint256 amount);

    error ZeroOwner();
    error ZeroAmount();
    /// @notice `to` has already consumed `nonce`. Replay protection is
    /// namespaced by recipient: a nonce is single-use for that recipient
    /// regardless of token or amount.
    error NonceReplayed(address to, bytes32 nonce);
    error BadRecipientSignature();
    error RecipientCallbackRejected(address recipient);
    /// @notice The production receipt-vault beacon no longer points at the
    /// implementation this orchestrator was built against.
    error VaultLogicMismatch(address expected, address actual);
    /// @notice The production receipt beacon no longer points at the
    /// implementation this orchestrator was built against.
    error ReceiptLogicMismatch(address expected, address actual);
    /// @notice The burn walk exhausted the orchestrator's held receipts for
    /// `token` with `shortfall` still unburned. Burning more than the
    /// orchestrator holds is an anomaly (interest-accrual overrun, mis-set
    /// pointer, receipts never transferred in) — recover manually, e.g.
    /// transfer receipts in or `setBurnIndex`, then retry.
    error InsufficientReceipts(address token, uint256 shortfall);
    /// @notice The vault reported an assets amount different from the shares
    /// requested. The share ratio is 1:1 by construction, so any mismatch
    /// means the vault is not behaving as this orchestrator was built to
    /// expect — halt loudly rather than continue on bad accounting.
    error VaultAmountMismatch(uint256 expected, uint256 actual);

    /// @notice Mint `amount` rebased tStocks of `token` to `to`. The receipt
    /// is minted to (and kept by) the orchestrator; the shares are forwarded
    /// to `to`, which must authorise the mint via `auth`.
    /// @param token The `OffchainAssetReceiptVault` to mint.
    /// @param to Recipient of the shares.
    /// @param amount Rebased tStock units to mint.
    /// @param auth The recipient's authorisation (see `MintAuthV1`).
    /// @param receiptInformation The MINTER's audit-trail payload, forwarded
    /// verbatim to `vault.mint` — not part of the recipient's authorisation.
    function mint(
        address token,
        address to,
        uint256 amount,
        MintAuthV1 calldata auth,
        bytes calldata receiptInformation
    ) external;

    /// @notice Burn `amount` rebased tStocks of `token`, pulled from the
    /// CALLER (burners always burn shares they hold — there is no burning out
    /// of third-party wallets), then walks the per-token pointer. Reverts
    /// `InsufficientReceipts` if the orchestrator's held receipts cannot
    /// cover `amount` — recover manually, never by minting.
    /// @param burnInfo `receiptInformation` forwarded to `vault.redeem` for
    /// the audit trail — e.g. a tag marking a debt-repay burn.
    function burn(address token, uint256 amount, bytes calldata burnInfo) external;

    /// @notice `EMERGENCY_ROLE` override of `token`'s burn pointer.
    function setBurnIndex(address token, uint256 newIndex) external;

    /// @notice `EMERGENCY_ROLE` escape hatch: pull a specific receipt out.
    function withdrawReceipt(address token, uint256 id, uint256 amount, address to) external;

    /// @notice `EMERGENCY_ROLE` escape hatch: sweep stranded tStocks out.
    function withdrawShares(address token, uint256 amount, address to) external;

    /// @notice `EMERGENCY_ROLE` escape hatch: rescue a foreign ERC-1155.
    function sweepERC1155(address erc1155, uint256 id, uint256 amount, address to) external;

    /// @notice `token`'s burn-walk pointer: the next receipt id `burn` will
    /// inspect.
    function nextBurnReceiptId(address token) external view returns (uint256);

    /// @notice True if `to` has already consumed `nonce`.
    function nonceUsed(address to, bytes32 nonce) external view returns (bool);

    /// @notice The EIP-712 digest a recipient signs (or checks in its
    /// `authorizeMint` callback) to authorise a mint.
    function mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) external view returns (Digest);

    /// @notice True if the production vault + receipt beacons currently point
    /// at the implementations this orchestrator expects (i.e. mint/burn are
    /// live rather than version-locked). Offchain convenience.
    function vaultLogicIsExpected() external view returns (bool);
}
