// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Float} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {EvaluableV4, SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

/// @dev An EIP-712 typed-data digest produced by the orchestrator's
/// `mintAuthDigest`. Aliased so the compiler rejects any `bytes32` that was
/// not explicitly produced as a digest (and vice versa).
type Digest is bytes32;

/// @dev A mint authorisation, produced by the recipient of a mint (never the
/// minter, which is responsible only for `receiptInformation`).
/// @param nonce Single-use per recipient: replay protection is namespaced by
/// `(to, nonce)`, so a recipient's nonce can never be replayed with a
/// different token or amount, and no third party can consume another
/// recipient's nonce.
/// @param signature EIP-712 signature by `to` over the digest of
/// `(token, to, amount, nonce)` — ECDSA for EOAs, EIP-1271 for contracts.
/// Empty triggers the `IMintRecipient.authorizeMint` callback on `to`
/// instead.
struct MintAuthV1 {
    bytes32 nonce;
    bytes signature;
}

/// @dev A leaky-bucket mint cap. Both policy numbers are Rain `Float`s in the
/// units of the mint weighting's output (see `setMintWeighting`), which is
/// what fills the bucket. Nothing about the token's corporate-action state
/// enters the cap path.
/// @param capacity The burst. The most one `mint` can take under this policy,
/// and the most that can be outstanding against it at one instant. Zero
/// admits nothing.
/// @param leakRate The sustained rate per second.
/// @param set True once a limit has been written. False is never set, which is
/// distinct from a zero capacity; both admit nothing.
struct MintLimitV1 {
    Float capacity;
    Float leakRate;
    bool set;
}

/// @dev A mint bucket: the leaky-bucket state for one cap, two words. A zero
/// level at a zero timestamp is an empty bucket at the epoch. The orchestrator
/// stores both words on every fill.
/// @param level The outstanding level at `timestamp`.
/// @param timestamp When `level` was recorded, in seconds.
struct MintBucketV1 {
    Float level;
    Float timestamp;
}

/// @title IST0xOrchestratorV1
/// @notice Full external interface of the ST0x orchestrator, the singleton
/// mint/burn proxy for the ST0x receipt-vault set.
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
    /// pointer and the receiver hook lowered the pointer to it.
    event BurnIndexLowered(address indexed token, uint256 oldIndex, uint256 newIndex);
    event ReceiptsWithdrawn(address indexed token, address indexed to, uint256 indexed id, uint256 amount);
    event SharesWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice A foreign ERC-1155 (not a production receipt) was swept out via
    /// `sweepERC1155`.
    event ForeignERC1155Swept(address indexed erc1155, address indexed to, uint256 indexed id, uint256 amount);
    /// @notice `MINT_ADMIN_ROLE` set `minter`'s mint limit: the one
    /// bucket metering that minter across every token and recipient.
    /// @param minter The minter the limit applies to.
    /// @param capacity The burst.
    /// @param leakRate The sustained rate per second.
    event MinterMintLimitSet(address indexed minter, Float capacity, Float leakRate);
    /// @notice `MINT_ADMIN_ROLE` set `recipient`'s mint limit: the one bucket
    /// metering everything minted to that recipient, across every token and
    /// minter.
    /// @param recipient The recipient the limit applies to.
    /// @param capacity The burst.
    /// @param leakRate The sustained rate per second.
    event RecipientMintLimitSet(address indexed recipient, Float capacity, Float leakRate);
    /// @notice `MINT_ADMIN_ROLE` set the mint weighting: the one expression
    /// that converts every mint, on every token, into the charge on both
    /// buckets.
    /// @param sender The `MINT_ADMIN_ROLE` caller that set it.
    /// @param evaluable The interpreter, store and bytecode now in force.
    event MintWeightingSet(address indexed sender, EvaluableV4 evaluable);

    error ZeroOwner();

    error ZeroAmount();
    /// @notice `mint` was asked to send the shares to the minter itself. The
    /// sender and the recipient of a mint can never be the same address.
    /// @param sender The `MINT_ROLE` caller that named itself as `to`.
    error SenderIsRecipient(address sender);
    /// @notice `to` has already consumed `nonce`. Replay protection is
    /// namespaced by recipient: a nonce is single-use for that recipient
    /// regardless of token or amount.
    error NonceReplayed(address to, bytes32 nonce);
    error BadRecipientSignature();
    error RecipientCallbackRejected(address recipient);
    /// @notice The production receipt-vault beacon does not point at the
    /// implementation this orchestrator was built against.
    error VaultLogicMismatch(address expected, address actual);
    /// @notice The production receipt beacon does not point at the
    /// implementation this orchestrator was built against.
    error ReceiptLogicMismatch(address expected, address actual);
    /// @notice The burn walk exhausted the orchestrator's held receipts for
    /// `token` with `shortfall` still unburned. The orchestrator never mints
    /// to cover a shortfall. Recovery is transferring receipts in or
    /// `setBurnIndex`, then retrying.
    error InsufficientReceipts(address token, uint256 shortfall);
    /// @notice The vault reported an assets amount different from the shares
    /// requested. The share ratio is 1:1.
    error VaultAmountMismatch(uint256 expected, uint256 actual);
    /// @notice A mint was metered against a minter limit that has never
    /// been set. A limit set with zero capacity reverts
    /// `MinterMintCapExceeded` instead.
    /// @param minter The `MINT_ROLE` caller with no minter limit.
    error MinterMintLimitUnset(address minter);
    /// @notice A mint was metered against a recipient limit that has never
    /// been set. A limit set with zero capacity reverts
    /// `RecipientMintCapExceeded` instead.
    /// @param recipient The `to` of the mint, with no limit.
    error RecipientMintLimitUnset(address recipient);
    /// @notice The mint did not fit the minter's bucket, which meters
    /// the minter across every token and recipient.
    /// @param minter The minter whose bucket refused the mint.
    /// @param capacity The minter's capacity in force, as stored.
    /// @param headroom What the minter's bucket would have accepted.
    /// @param charge What the mint was charged against the bucket.
    error MinterMintCapExceeded(address minter, Float capacity, Float headroom, Float charge);
    /// @notice The mint did not fit the recipient's bucket, which meters
    /// everything minted to that recipient across every token and minter.
    /// @param recipient The `to` whose bucket refused the mint.
    /// @param capacity The recipient's capacity in force, as stored.
    /// @param headroom What the recipient's bucket would have accepted.
    /// @param charge What the mint was charged against the bucket.
    error RecipientMintCapExceeded(address recipient, Float capacity, Float headroom, Float charge);
    error NegativeMintLimitCapacity(Float capacity);
    error NegativeMintLimitLeakRate(Float leakRate);
    /// @notice A mint was requested before any mint weighting was set.
    error MintWeightingUnset();
    /// @notice The mint weighting evaluated to an empty stack, so there is no
    /// charge. The expression must leave at least one output; the last one is
    /// the charge.
    /// @param outputs How many outputs the expression left.
    error UnsupportedMintWeightingOutputs(uint256 outputs);

    /// @notice Mint `amount` rebased tStocks of `token` to `to`. The receipt
    /// is minted to (and kept by) the orchestrator; the shares are forwarded
    /// to `to`, which must authorise the mint via `auth`.
    ///
    /// The minter can never be the recipient: `to == msg.sender` reverts
    /// `SenderIsRecipient`, checked before anything is metered or authorised.
    ///
    /// Metered by two leaky buckets, both of which must accept: the minter's
    /// (`msg.sender`) bucket and the recipient's (`to`) bucket. Nothing
    /// is metered per token. Either rejection reverts with
    /// `MinterMintCapExceeded` or `RecipientMintCapExceeded`, or with
    /// `MinterMintLimitUnset` / `RecipientMintLimitUnset` where the
    /// limit was never set at all.
    ///
    /// What both buckets are charged is the value the mint weighting puts on
    /// this mint: the mint admin's expression (`setMintWeighting`) is
    /// evaluated over the mint (`token`'s symbol and `amount` as a `Float` of
    /// whole tokens) and `attestations`, and its last output is the charge.
    /// The expression decides what the attestations must say and reverts the
    /// mint if they do not say it. `MintWeightingUnset` if no expression has
    /// been set; a zero or negative charge is refused by the bucket by name.
    /// @param token The `OffchainAssetReceiptVault` to mint.
    /// @param to Recipient of the shares.
    /// @param amount Rebased tStock units to mint.
    /// @param auth The recipient's authorisation (see `MintAuthV1`).
    /// @param receiptInformation The MINTER's audit-trail payload, forwarded
    /// verbatim to `vault.mint` — not part of the recipient's authorisation.
    /// @param attestations The signed attestations the weighting reads, the
    /// lead's first, each `[symbol, price, time]` (see
    /// `LibSt0xAttestContext`). Every signature is verified before the
    /// expression runs; what the signed values must be is the expression's
    /// decision. Not part of the recipient's authorisation.
    function mint(
        address token,
        address to,
        uint256 amount,
        MintAuthV1 calldata auth,
        bytes calldata receiptInformation,
        SignedContextV1[] calldata attestations
    ) external;

    /// @notice Burn `amount` rebased tStocks of `token`, pulled from the
    /// caller, then walk the per-token pointer. Reverts
    /// `InsufficientReceipts` if the orchestrator's held receipts cannot
    /// cover `amount`.
    /// @param burnInfo `receiptInformation` forwarded to `vault.redeem`.
    function burn(address token, uint256 amount, bytes calldata burnInfo) external;

    /// @notice `EMERGENCY_ROLE` override of `token`'s burn pointer.
    function setBurnIndex(address token, uint256 newIndex) external;

    /// @notice `EMERGENCY_ROLE` escape hatch: pull a specific receipt out.
    function withdrawReceipt(address token, uint256 id, uint256 amount, address to) external;

    /// @notice `EMERGENCY_ROLE` escape hatch: sweep stranded tStocks out.
    function withdrawShares(address token, uint256 amount, address to) external;

    /// @notice `EMERGENCY_ROLE` escape hatch: rescue a foreign ERC-1155.
    function sweepERC1155(address erc1155, uint256 id, uint256 amount, address to) external;

    /// @notice `MINT_ADMIN_ROLE` sets `minter`'s mint limit: one bucket
    /// covering every mint by `minter`, across all tokens and recipients.
    /// @param minter The `MINT_ROLE` holder the limit applies to.
    /// @param capacity Burst, in the units mints are charged in (see
    /// `MintLimitV1`).
    /// @param leakRate Sustained rate in those same units per second.
    function setMinterMintLimit(address minter, Float capacity, Float leakRate) external;

    /// @notice `MINT_ADMIN_ROLE` sets `recipient`'s mint limit: one bucket
    /// covering everything minted to `recipient`, across all tokens and
    /// minters. A zero `capacity` is a set limit that admits nothing, distinct
    /// from never having been set.
    /// @param recipient The mint `to` the limit applies to.
    /// @param capacity Burst, as for `setMinterMintLimit`.
    /// @param leakRate Sustained rate in those same units per second.
    function setRecipientMintLimit(address recipient, Float capacity, Float leakRate) external;

    /// @notice `MINT_ADMIN_ROLE` sets the mint weighting: the one Rainlang
    /// expression, global across every token, minter and recipient, that
    /// converts a mint into the value both buckets are charged.
    ///
    /// The expression is evaluated by `evaluable.interpreter` over the context
    /// grid `LibSt0xAttestContext` builds — the mint's symbol and amount, then
    /// the attestations passed to `mint` — and must leave at least one
    /// output, the last of which is the charge. Any state it writes is
    /// persisted to `evaluable.store` under the orchestrator's namespace.
    ///
    /// Stored as given. The interpreter and store are trusted by whoever sets
    /// them: a zero interpreter is the same as no weighting and every mint
    /// reverts `MintWeightingUnset`.
    /// @param evaluable The interpreter, store and bytecode to evaluate.
    function setMintWeighting(EvaluableV4 calldata evaluable) external;

    /// @notice `token`'s burn-walk pointer: the next receipt id `burn` will
    /// inspect.
    function nextBurnReceiptId(address token) external view returns (uint256);

    /// @notice True if `to` has already consumed `nonce`.
    function nonceUsed(address to, bytes32 nonce) external view returns (bool);

    /// @notice The EIP-712 digest a recipient signs (or checks in its
    /// `authorizeMint` callback) to authorise a mint.
    function mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) external view returns (Digest);

    /// @notice `minter`'s mint limit, as stored.
    function minterMintLimit(address minter) external view returns (MintLimitV1 memory);

    /// @notice `recipient`'s mint limit, as stored.
    function recipientMintLimit(address recipient) external view returns (MintLimitV1 memory);

    /// @notice The mint weighting in force, as stored. A zero interpreter
    /// means none has been set.
    function mintWeighting() external view returns (EvaluableV4 memory);

    /// @notice The largest charge a `mint(…, recipient, …)` by `minter` would
    /// accept at the current block timestamp, for any token: the smaller of
    /// the minter's headroom and the recipient's. Zero when either
    /// limit is unset. Nothing in the enforcement path reads it.
    function mintHeadroom(address minter, address recipient) external view returns (Float);

    /// @notice True if the production vault + receipt beacons currently point
    /// at the implementations this orchestrator expects, so `mint`/`burn` are
    /// not version-locked.
    function vaultLogicIsExpected() external view returns (bool);
}
