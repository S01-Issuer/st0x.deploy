// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Float} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {EvaluableV4, SignedContextV2} from "rainlang-0.2.32/src/interface/IInterpreterCallerV5.sol";

import {Digest, MintAuthV1} from "./deprecated/IST0xOrchestratorV1.sol";

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

/// @dev Which of a mint's two buckets a cap is: the minter's, across every
/// token and recipient, or the recipient's, across every token and minter.
enum MintCapKind {
    Minter,
    Recipient
}

/// @title IST0xOrchestratorV2
/// @notice Full external interface of the ST0x orchestrator, the singleton
/// mint/burn proxy for the ST0x receipt-vault set. Supersedes
/// `IST0xOrchestratorV1`: `mint` takes the signed context the mint weighting
/// reads, and every mint is metered by the minter and recipient mint caps.
interface IST0xOrchestratorV2 {
    event Minted(
        address indexed sender, address indexed token, address indexed recipient, uint256 amount, bytes32 nonce
    );
    /// @param firstReceiptId `nextBurnReceiptId[token]` at the start of the call.
    /// @param nextBurnReceiptIdAfter The pointer at the end of the call. The
    /// walk only ever moves forward within a burn, so `[firstReceiptId,
    /// nextBurnReceiptIdAfter)` is the consumed id range.
    event Burned(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 firstReceiptId,
        uint256 nextBurnReceiptIdAfter
    );
    /// @notice `EMERGENCY_ROLE` manually overrode `token`'s burn pointer.
    event BurnIndexSet(address indexed sender, address indexed token, uint256 oldIndex, uint256 newIndex);
    /// @notice A production receipt arrived at an id below `token`'s burn
    /// pointer and the receiver hook lowered the pointer to it.
    event BurnIndexLowered(address indexed sender, address indexed token, uint256 oldIndex, uint256 newIndex);
    event ReceiptsWithdrawn(
        address indexed sender, address indexed token, address indexed to, uint256 id, uint256 amount
    );
    event SharesWithdrawn(address indexed sender, address indexed token, address indexed to, uint256 amount);
    /// @notice A foreign ERC-1155 (not a production receipt) was swept out via
    /// `sweepERC1155`.
    event ForeignERC1155Swept(
        address indexed sender, address indexed erc1155, address indexed to, uint256 id, uint256 amount
    );
    /// @notice `MINT_ADMIN_ROLE` set `account`'s `kind` mint limit.
    /// @param kind Which bucket.
    /// @param account The minter or recipient the limit applies to.
    /// @param capacity The burst.
    /// @param leakRate The sustained rate per second.
    event MintLimitSet(
        address indexed sender, MintCapKind indexed kind, address indexed account, Float capacity, Float leakRate
    );
    /// @notice `MINT_ADMIN_ROLE` set the mint weighting: the one expression
    /// that converts every mint, on every token, into the charge on both
    /// buckets.
    /// @param sender The `MINT_ADMIN_ROLE` caller that set it.
    /// @param evaluable The interpreter, store and bytecode now in force.
    event MintWeightingSet(address indexed sender, EvaluableV4 evaluable);

    error ZeroAmount();
    /// @notice `mint` was asked to send the shares to the minter itself. The
    /// sender and the recipient of a mint can never be the same address.
    /// @param sender The `MINT_ROLE` caller that named itself as `recipient`.
    error SenderIsRecipient(address sender);
    /// @notice `recipient` has already consumed `nonce`. Replay protection is
    /// namespaced by recipient: a nonce is single-use for that recipient
    /// regardless of token or amount.
    error NonceReplayed(address recipient, bytes32 nonce);
    error BadRecipientSignature();
    error RecipientCallbackRejected(address recipient);
    /// @notice `account`, a token or its receipt, is not a registry beacon
    /// proxy.
    error NotRegistryBeaconProxy(address account);
    /// @notice The token's beacon serves a vault implementation other than the
    /// one this orchestrator was built against.
    error VaultLogicMismatch(address expected, address actual);
    /// @notice The token's receipt's beacon serves a receipt implementation
    /// other than the one this orchestrator was built against.
    error ReceiptLogicMismatch(address expected, address actual);
    /// @notice The burn walk exhausted the orchestrator's held receipts for
    /// `token` with `shortfall` still unburned. The orchestrator never mints
    /// to cover a shortfall. Recovery is transferring receipts in or
    /// `setBurnIndex`, then retrying.
    error InsufficientReceipts(address token, uint256 shortfall);
    /// @notice The vault reported an assets amount different from the shares
    /// requested. The share ratio is 1:1.
    error VaultAmountMismatch(uint256 expected, uint256 actual);
    /// @notice A mint was metered against a limit that has never been set. A
    /// limit set with zero capacity reverts `MintCapExceeded` instead.
    /// @param kind Which bucket has no limit.
    /// @param account The minter or recipient with no limit.
    error MintLimitUnset(MintCapKind kind, address account);
    /// @notice The mint did not fit `account`'s `kind` bucket.
    /// @param kind Which bucket refused the mint.
    /// @param account The minter or recipient whose bucket refused the mint.
    /// @param capacity The capacity in force, as stored.
    /// @param headroom What the bucket would have accepted.
    /// @param charge What the mint was charged against the bucket.
    error MintCapExceeded(MintCapKind kind, address account, Float capacity, Float headroom, Float charge);
    /// @notice A mint was requested before any mint weighting was set.
    error MintWeightingUnset();
    /// @notice The token's symbol is longer than the 31 bytes the mint
    /// weighting's context can carry. Refused rather than truncated, since a
    /// truncated symbol can be another token's.
    /// @param token The token being minted.
    /// @param length The symbol's length in bytes.
    error MintSymbolTooLong(address token, uint256 length);
    /// @notice The mint weighting evaluated to an empty stack, so there is no
    /// charge. The expression must leave at least one output; the last one is
    /// the charge.
    /// @param outputs How many outputs the expression left.
    error UnsupportedMintWeightingOutputs(uint256 outputs);

    /// @notice Mint `amount` rebased tStocks of `token` to `recipient`. The receipt
    /// is minted to (and kept by) the orchestrator; the shares are forwarded
    /// to `recipient`, which must authorise the mint via `auth`.
    ///
    /// The minter can never be the recipient: `recipient == msg.sender` reverts
    /// `SenderIsRecipient`, checked before anything is metered or authorised.
    ///
    /// Metered by two leaky buckets, both of which must accept: the minter's
    /// (`msg.sender`) bucket and the recipient's bucket. Nothing
    /// is metered per token. Either rejection reverts with `MintCapExceeded`,
    /// or with `MintLimitUnset` where the limit was never set at all, each
    /// naming the bucket's `MintCapKind`.
    ///
    /// What both buckets are charged is the value the mint weighting puts on
    /// this mint: the mint admin's expression (`setMintWeighting`) is
    /// evaluated over the mint (`token`'s symbol and `amount` as a `Float` of
    /// whole tokens) and `signedContext`, and its last output is the charge.
    /// The expression decides what `signedContext` must contain and reverts
    /// the mint if it does not. `MintWeightingUnset` if no expression has
    /// been set; a zero or negative charge is refused by the bucket by name.
    /// @param token The `OffchainAssetReceiptVault` to mint.
    /// @param recipient Receives the shares.
    /// @param amount Rebased tStock units to mint.
    /// @param auth The recipient's authorisation (see `MintAuthV1`).
    /// @param receiptInformation The MINTER's audit-trail payload, forwarded
    /// verbatim to `vault.mint` — not part of the recipient's authorisation.
    /// @param signedContext Signed context the weighting reads. Every
    /// signature is verified under the domain separator it names before the
    /// expression runs; what it must contain is the expression's decision.
    /// Not part of the recipient's authorisation.
    function mint(
        address token,
        address recipient,
        uint256 amount,
        MintAuthV1 calldata auth,
        bytes calldata receiptInformation,
        SignedContextV2[] calldata signedContext
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

    /// @notice `MINT_ADMIN_ROLE` sets `account`'s `kind` mint limit. A zero
    /// `capacity` is a set limit that admits nothing, distinct from never
    /// having been set.
    /// @param kind Which bucket.
    /// @param account The `MINT_ROLE` holder or mint recipient the limit applies to.
    /// @param capacity Burst, in the units mints are charged in (see
    /// `MintLimitV1`).
    /// @param leakRate Sustained rate in those same units per second.
    function setMintLimit(MintCapKind kind, address account, Float capacity, Float leakRate) external;

    /// @notice `MINT_ADMIN_ROLE` sets the mint weighting: the one Rainlang
    /// expression, global across every token, minter and recipient, that
    /// converts a mint into the value both buckets are charged.
    ///
    /// The expression is evaluated by `evaluable.interpreter` over the context
    /// grid `LibSt0xAttestContext` builds — the mint's symbol and amount, then
    /// the signed context passed to `mint` — and must leave at least one
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

    /// @notice True if `recipient` has already consumed `nonce`.
    function nonceUsed(address recipient, bytes32 nonce) external view returns (bool);

    /// @notice The EIP-712 digest a recipient signs (or checks in its
    /// `authorizeMint` callback) to authorise a mint.
    function mintAuthDigest(address token, address recipient, uint256 amount, bytes32 nonce)
        external
        view
        returns (Digest);

    /// @notice `account`'s `kind` mint limit, as stored.
    function mintLimit(MintCapKind kind, address account) external view returns (MintLimitV1 memory);

    /// @notice The mint weighting in force, as stored. A zero interpreter
    /// means none has been set.
    function mintWeighting() external view returns (EvaluableV4 memory);

    /// @notice The largest charge a `mint(…, recipient, …)` by `minter` would
    /// accept at the current block timestamp, for any token: the smaller of
    /// the minter's headroom and the recipient's. Zero when either
    /// limit is unset. Nothing in the enforcement path reads it.
    function mintHeadroom(address minter, address recipient) external view returns (Float);

    /// @notice The level outstanding in `account`'s `kind` bucket at the
    /// current block timestamp, after leak at the stored rate. Zero for a
    /// bucket never filled, set or not.
    function mintLevel(MintCapKind kind, address account) external view returns (Float);

    /// @notice True if `token` and its receipt are registry beacon proxies
    /// whose beacons serve the implementations this orchestrator expects, so
    /// mint/burn on `token` pass the vault-logic guard.
    function vaultLogicIsExpected(address token) external view returns (bool);
}
