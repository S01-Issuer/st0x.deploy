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

/// @dev A leaky-bucket mint cap, denominated in GENESIS units: eighteen
/// decimal tStock units as they were before any corporate action completed.
///
/// `mint`'s `amount` arrives in CURRENT rebased units and is converted to
/// genesis units before it is metered, so a rebase rescales what this policy
/// authorises in current units by construction. There is no second
/// transaction to sequence behind a corporate action and no window in which a
/// stored cap means something other than what governance approved.
///
/// A token with no completed balance-migration action has a cumulative
/// multiplier of one, so genesis and current units coincide there; the two
/// denominations only diverge once an action has completed.
/// @param capacity The burst, in genesis units. The most one `mint` can take
/// under this policy, and the most that can be outstanding against it at one
/// instant. Zero admits nothing.
/// @param leakRate The sustained rate, in genesis units per second.
struct MintLimitV1 {
    uint256 capacity;
    uint256 leakRate;
}

/// @dev A per-`(minter, token)` override of the per-token default mint limit.
/// The `set` marker distinguishes a deliberate zero from no override.
/// @param set True once an override has been written for the pair. False
/// means the pair falls through to the per-token default.
/// @param limit The override policy. Only consulted when `set` is true.
struct MintLimitOverrideV1 {
    bool set;
    MintLimitV1 limit;
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
    /// @notice Admin replaced the global mint limit.
    /// @param denominationToken The token whose genesis denomination the
    /// admin priced this global cap against, and whose cursor the set was
    /// pinned to. Recorded so a global cap's pricing basis is on chain rather
    /// than only in the proposal text.
    /// @param completedActionCount `denominationToken`'s cursor at the set.
    /// @param capacity The burst, in genesis units.
    /// @param leakRate The sustained rate, in genesis units per second.
    event GlobalMintLimitSet(
        address indexed denominationToken, uint256 completedActionCount, uint256 capacity, uint256 leakRate
    );
    /// @notice Admin replaced `token`'s default mint limit.
    /// @param token The token whose default was replaced.
    /// @param completedActionCount `token`'s cursor at the set.
    /// @param capacity The burst, in genesis units.
    /// @param leakRate The sustained rate, in genesis units per second.
    event TokenMintLimitSet(address indexed token, uint256 completedActionCount, uint256 capacity, uint256 leakRate);
    /// @notice Admin wrote the `(minter, token)` override, which takes
    /// precedence over `token`'s default.
    /// @param minter The minter the override applies to.
    /// @param token The token the override applies to.
    /// @param completedActionCount `token`'s cursor at the set.
    /// @param capacity The burst, in genesis units.
    /// @param leakRate The sustained rate, in genesis units per second.
    event MinterMintLimitSet(
        address indexed minter, address indexed token, uint256 completedActionCount, uint256 capacity, uint256 leakRate
    );
    /// @notice Admin removed the `(minter, token)` override.
    event MinterMintLimitCleared(address indexed minter, address indexed token);

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
    /// @notice The mint did not fit the global bucket. Every numeric field is
    /// in GENESIS units — the denomination the buckets are metered in — so
    /// `amount` is the offered `mint` amount after its current-to-genesis
    /// conversion, not the number the caller passed.
    /// @param capacity The global capacity in force, in genesis units.
    /// @param headroom What the global bucket would have accepted, in genesis
    /// units.
    /// @param amount The offered amount converted to genesis units.
    error GlobalMintCapExceeded(uint256 capacity, uint256 headroom, uint256 amount);
    /// @notice The mint did not fit the `(minter, token)` bucket. Every
    /// numeric field is in GENESIS units, as for `GlobalMintCapExceeded`.
    /// @param minter The `MINT_ROLE` caller whose bucket rejected the mint.
    /// @param token The token whose bucket rejected the mint.
    /// @param capacity The capacity in force for the pair, in genesis units.
    /// @param headroom What the pair's bucket would have accepted, in genesis
    /// units.
    /// @param amount The offered amount converted to genesis units.
    error MinterMintCapExceeded(address minter, address token, uint256 capacity, uint256 headroom, uint256 amount);
    /// @notice A cap setter was given an expected cursor that is not the
    /// token's current `completedActionCount()`.
    ///
    /// Caps are written in genesis units, so an admin who approves a figure
    /// in current units converts it at proposal time. Governance is
    /// timelocked: if an action completes between the proposal and its
    /// execution, that conversion no longer holds and the same genesis number
    /// now authorises a different quantity in current units than the one that
    /// was approved. This error is that event surfaced as a revert rather
    /// than as a silently mispriced cap — the admin re-proposes against a
    /// denomination they can actually see.
    /// @param token The token whose cursor was checked. For the global limit
    /// this is the denomination token the setter was given.
    /// @param expectedActionCount The cursor the caller priced against.
    /// @param actualActionCount The token's cursor now.
    error MintLimitCursorMoved(address token, uint256 expectedActionCount, uint256 actualActionCount);

    /// @notice Mint `amount` rebased tStocks of `token` to `to`. The receipt
    /// is minted to (and kept by) the orchestrator; the shares are forwarded
    /// to `to`, which must authorise the mint via `auth`.
    ///
    /// Metered by two leaky buckets, both of which must accept: the global
    /// bucket, and the `(msg.sender, token)` bucket under the pair's override
    /// if set, else `token`'s default. Either rejection reverts with
    /// `GlobalMintCapExceeded` or `MinterMintCapExceeded`.
    ///
    /// Both buckets are denominated in genesis units, so `amount` is
    /// converted with `token`'s cumulative balance multiplier — rounding UP,
    /// because it is the amount being charged — before either is metered.
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

    /// @notice `DEFAULT_ADMIN_ROLE` sets the global mint limit: one bucket
    /// covering every mint, across all minters and all tokens.
    ///
    /// ## Why a global cap names a denomination token
    ///
    /// The global bucket is not per-token, so no single token's cursor is
    /// *its* cursor, and per-token cursors disagree. The cap itself needs no
    /// re-pricing after an action — it is stored in genesis units, which no
    /// corporate action moves. What is conversion-sensitive is the admin's
    /// own arithmetic: a global cap is approved as a figure in the current
    /// units of whichever token the admin priced it against, and converted to
    /// genesis units with that token's multiplier. Only the admin knows which
    /// token that was, so the setter is told, and pins it. Naming it also
    /// puts the pricing basis of a global cap on chain (see
    /// `GlobalMintLimitSet`) instead of leaving it in the proposal text.
    ///
    /// An admin who genuinely priced in genesis units can name any live token
    /// and its current cursor; the pin then simply asserts something that was
    /// already true. There is deliberately no "no reference" escape value: an
    /// admin who *did* convert and reached for it by mistake would get back
    /// exactly the silent mispricing this argument exists to prevent.
    /// @param denominationToken The token whose genesis denomination the cap
    /// was priced against. Must answer `completedActionCount()`.
    /// @param expectedActionCount `denominationToken`'s
    /// `completedActionCount()` as at pricing. Reverts
    /// `MintLimitCursorMoved` if it has moved since.
    /// @param capacity Burst, in 18-decimal GENESIS units. Reverts
    /// `LeakyBucketCapacityOverflow` if it does not fit the bucket codec's
    /// level field.
    /// @param leakRate Sustained rate in genesis units per second.
    function setGlobalMintLimit(
        address denominationToken,
        uint256 expectedActionCount,
        uint256 capacity,
        uint256 leakRate
    ) external;

    /// @notice `DEFAULT_ADMIN_ROLE` sets `token`'s default mint limit, which
    /// applies to every minter with no override for `token`.
    /// @param token The token the default applies to.
    /// @param expectedActionCount `token`'s `completedActionCount()` as at
    /// pricing. Reverts `MintLimitCursorMoved` if it has moved since.
    /// @param capacity Burst, in 18-decimal GENESIS units.
    /// @param leakRate Sustained rate in genesis units per second.
    function setTokenMintLimit(address token, uint256 expectedActionCount, uint256 capacity, uint256 leakRate) external;

    /// @notice `DEFAULT_ADMIN_ROLE` sets the `(minter, token)` override, which
    /// takes precedence over `token`'s default. A zero `capacity` here is a
    /// set override that admits nothing, distinct from having no override.
    /// @param minter The `MINT_ROLE` holder the override applies to.
    /// @param token The token the override applies to.
    /// @param expectedActionCount `token`'s `completedActionCount()` as at
    /// pricing. Reverts `MintLimitCursorMoved` if it has moved since.
    /// @param capacity Burst, in 18-decimal GENESIS units.
    /// @param leakRate Sustained rate in genesis units per second.
    function setMinterMintLimit(
        address minter,
        address token,
        uint256 expectedActionCount,
        uint256 capacity,
        uint256 leakRate
    ) external;

    /// @notice `DEFAULT_ADMIN_ROLE` removes the `(minter, token)` override, so
    /// the pair falls back to `token`'s default. The pair's bucket level is
    /// untouched.
    ///
    /// Takes no cursor, and that is the same rule the setters follow rather
    /// than an exception to it. A cursor pins an admin's *conversion*, and
    /// this writes no converted number: it names no capacity, and the default
    /// it falls back to is already stored in genesis units, so a completed
    /// action between proposal and execution cannot change what this call
    /// does.
    /// @param minter The `MINT_ROLE` holder whose override is removed.
    /// @param token The token the override is removed for.
    function clearMinterMintLimit(address minter, address token) external;

    /// @notice `token`'s burn-walk pointer: the next receipt id `burn` will
    /// inspect.
    function nextBurnReceiptId(address token) external view returns (uint256);

    /// @notice True if `to` has already consumed `nonce`.
    function nonceUsed(address to, bytes32 nonce) external view returns (bool);

    /// @notice The EIP-712 digest a recipient signs (or checks in its
    /// `authorizeMint` callback) to authorise a mint.
    function mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) external view returns (Digest);

    /// @notice The global mint limit currently in force, as stored: GENESIS
    /// units, the denomination the setters take.
    function globalMintLimit() external view returns (MintLimitV1 memory);

    /// @notice `token`'s default mint limit, used by any minter with no
    /// override for `token`. GENESIS units, as stored.
    function tokenMintLimit(address token) external view returns (MintLimitV1 memory);

    /// @notice The raw `(minter, token)` override, including whether one is
    /// set at all. GENESIS units, as stored.
    function minterMintLimitOverride(address minter, address token) external view returns (MintLimitOverrideV1 memory);

    /// @notice The resolved per-pair policy `mint` meters `(minter, token)`
    /// against: the override if one is set, else `token`'s default. The global
    /// limit is a separate bucket and is not folded in here. GENESIS units, as
    /// stored.
    function mintLimit(address minter, address token) external view returns (MintLimitV1 memory);

    /// @notice The largest `amount` a `mint(token, …)` by `minter` would
    /// accept at the current block timestamp: the smaller of the global
    /// bucket's headroom and the pair's. Nothing in the enforcement path reads
    /// it.
    ///
    /// Unlike the policy views above this answers in CURRENT rebased units,
    /// because it answers the question "what may I pass as `amount`". The
    /// genesis headroom is converted with `token`'s multiplier rounding DOWN,
    /// so the number really is accepted rather than being one wei too large.
    ///
    /// Reverts (`FixedDecimalOverflow`) if the current-unit headroom does not
    /// fit a `uint256` — a headroom no `amount` could name in the first place.
    function mintHeadroom(address minter, address token) external view returns (uint256);

    /// @notice True if the production vault + receipt beacons currently point
    /// at the implementations this orchestrator expects (i.e. mint/burn are
    /// live rather than version-locked). Offchain convenience.
    function vaultLogicIsExpected() external view returns (bool);
}
