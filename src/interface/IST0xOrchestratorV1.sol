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

/// @dev A leaky-bucket mint cap. Both fields are denominated in the SAME
/// units as `mint`'s `amount` argument — current rebased tStock units, 18
/// decimals, so one whole tStock is `1e18`. There is no conversion layer:
/// the numbers governance writes here are the numbers the bucket meters.
/// @param capacity The burst: the most a single `mint` can ever take under
/// this policy, and the most that can be outstanding against it at one
/// instant. Elapsed time never enlarges it, so this is the number that has to
/// be survivable on its own if the key it governs is compromised at the worst
/// moment. A capacity of `0` admits nothing, which is what an unset policy
/// resolves to.
/// @param leakRate The sustained rate, in the same units PER SECOND. `1e18`
/// is one whole tStock per second. It controls how often a burst can be
/// repeated, never how large one can be. A policy written as "X per day" is
/// `X / 86400`, rounded DOWN offchain so the onchain rate is never faster
/// than the policy.
struct MintLimitV1 {
    uint256 capacity;
    uint256 leakRate;
}

/// @dev A per-`(minter, token)` override of the per-token default mint limit,
/// carrying an explicit `set` marker.
///
/// The marker exists so that a deliberate zero is expressible. Without it a
/// `capacity` of `0` is indistinguishable from "no override configured", and
/// admins could not pin one minter to zero for one token while the token's
/// default stays non-zero — the only alternative being to revoke `MINT_ROLE`,
/// which stops that minter minting EVERY token. `set` keeps
/// "unset ⇒ 0 ⇒ fail closed" intact while making "this minter may not mint
/// this token" a first-class setting.
/// @param set True once an override has been written for the pair. False —
/// the default for untouched storage — means the pair falls through to the
/// per-token default.
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
    /// @notice Admin replaced the global mint limit — the one bucket every
    /// mint passes through, whatever the minter and whatever the token.
    event GlobalMintLimitSet(uint256 capacity, uint256 leakRate);
    /// @notice Admin replaced `token`'s DEFAULT mint limit, which applies to
    /// every minter that has no override for `token`.
    event TokenMintLimitSet(address indexed token, uint256 capacity, uint256 leakRate);
    /// @notice Admin wrote an override for `(minter, token)`. It takes
    /// precedence over `token`'s default, including when `capacity` is zero —
    /// a zero override is a deliberate "this minter may not mint this token".
    event MinterMintLimitSet(address indexed minter, address indexed token, uint256 capacity, uint256 leakRate);
    /// @notice Admin removed the `(minter, token)` override, so the pair falls
    /// back to `token`'s default.
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
    /// @notice The mint did not fit the GLOBAL bucket — the one every mint
    /// passes through. Named separately from the per-pair rejection so the
    /// revert says which cap bound. A global capacity that was never
    /// configured is `0`, and every mint is rejected here until admin sets
    /// one.
    /// @param capacity The global capacity in force.
    /// @param headroom What the global bucket would have accepted, after the
    /// leak accrued since its last fill.
    /// @param amount The amount that was offered.
    error GlobalMintCapExceeded(uint256 capacity, uint256 headroom, uint256 amount);
    /// @notice The mint did not fit the `(minter, token)` bucket. The policy
    /// in force is the pair's override if one is set, else `token`'s default;
    /// both are `0` until configured, and a zero capacity admits nothing.
    /// @param minter The `MINT_ROLE` caller whose bucket rejected the mint.
    /// @param token The token whose bucket rejected the mint.
    /// @param capacity The capacity in force for the pair.
    /// @param headroom What the pair's bucket would have accepted, after the
    /// leak accrued since its last fill.
    /// @param amount The amount that was offered.
    error MinterMintCapExceeded(address minter, address token, uint256 capacity, uint256 headroom, uint256 amount);

    /// @notice Mint `amount` rebased tStocks of `token` to `to`. The receipt
    /// is minted to (and kept by) the orchestrator; the shares are forwarded
    /// to `to`, which must authorise the mint via `auth`.
    ///
    /// Metered by TWO leaky buckets, both of which must accept: the global
    /// bucket, and the `(msg.sender, token)` bucket under the pair's override
    /// (if set) else `token`'s default. Either rejection reverts the whole
    /// mint, with `GlobalMintCapExceeded` or `MinterMintCapExceeded` naming
    /// which one bound. Every limit is `0` until admin sets it, and a zero
    /// capacity admits nothing, so a fresh deployment, a new token and a new
    /// minter all start unable to mint.
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

    /// @notice `DEFAULT_ADMIN_ROLE` sets the GLOBAL mint limit: one bucket
    /// covering every mint, across all minters and all tokens. Lowering it
    /// below the outstanding level binds immediately — headroom reads zero
    /// and the bucket leaks down under the new policy — so there is no window
    /// for a minter to front-run the change.
    /// @param capacity Burst, in 18-decimal rebased tStock units. Must fit the
    /// bucket codec's level field or the call reverts
    /// `LeakyBucketCapacityOverflow`, so an unenforceable policy is refused
    /// where it is written rather than where it is used.
    /// @param leakRate Sustained rate in the same units per second.
    function setGlobalMintLimit(uint256 capacity, uint256 leakRate) external;

    /// @notice `DEFAULT_ADMIN_ROLE` sets `token`'s DEFAULT mint limit, which
    /// applies to every minter with no override for `token`.
    /// @param token The token the default applies to.
    /// @param capacity Burst, in 18-decimal rebased tStock units.
    /// @param leakRate Sustained rate in the same units per second.
    function setTokenMintLimit(address token, uint256 capacity, uint256 leakRate) external;

    /// @notice `DEFAULT_ADMIN_ROLE` sets the `(minter, token)` override, which
    /// takes precedence over `token`'s default. Setting `capacity` to zero
    /// here is a deliberate, first-class "this minter may not mint this
    /// token", distinct from having no override — and narrower than revoking
    /// `MINT_ROLE`, which would stop that minter minting every token.
    /// @param minter The `MINT_ROLE` holder the override applies to.
    /// @param token The token the override applies to.
    /// @param capacity Burst, in 18-decimal rebased tStock units.
    /// @param leakRate Sustained rate in the same units per second.
    function setMinterMintLimit(address minter, address token, uint256 capacity, uint256 leakRate) external;

    /// @notice `DEFAULT_ADMIN_ROLE` removes the `(minter, token)` override, so
    /// the pair falls back to `token`'s default. The pair's bucket LEVEL is
    /// untouched: clearing an override changes the policy, never the credit
    /// already consumed.
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

    /// @notice The GLOBAL mint limit currently in force.
    function globalMintLimit() external view returns (MintLimitV1 memory);

    /// @notice `token`'s DEFAULT mint limit — what a minter with no override
    /// for `token` is metered against.
    function tokenMintLimit(address token) external view returns (MintLimitV1 memory);

    /// @notice The raw `(minter, token)` override, including whether one is
    /// set at all. `set == false` means the pair uses `token`'s default; a set
    /// override with a zero capacity means the pair may not mint.
    function minterMintLimitOverride(address minter, address token) external view returns (MintLimitOverrideV1 memory);

    /// @notice The RESOLVED per-pair policy `mint` meters `(minter, token)`
    /// against: the override if one is set, else `token`'s default. The global
    /// limit is a separate bucket and is not folded in here — see
    /// `mintHeadroom` for what actually fits.
    function mintLimit(address minter, address token) external view returns (MintLimitV1 memory);

    /// @notice The largest `amount` a `mint(token, …)` by `minter` would
    /// accept at the current block timestamp: the smaller of the global
    /// bucket's headroom and the pair's. Exactly this amount fits and one unit
    /// more reverts. Offchain convenience; nothing in the enforcement path
    /// reads it.
    function mintHeadroom(address minter, address token) external view returns (uint256);

    /// @notice True if the production vault + receipt beacons currently point
    /// at the implementations this orchestrator expects (i.e. mint/burn are
    /// live rather than version-locked). Offchain convenience.
    function vaultLogicIsExpected() external view returns (bool);
}
