// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {SignatureChecker} from "@openzeppelin-contracts-5.6.1/utils/cryptography/SignatureChecker.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {IReceiptV3} from "rain-vats-0.1.6/src/interface/IReceiptV3.sol";
import {ReceiptVault} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";

import {LibLeakyBucketCheckpoint} from "rain-lib-leakybucket-0.1.4/src/lib/LibLeakyBucketCheckpoint.sol";

import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {IMintRecipient} from "../interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";
import {
    IST0xOrchestratorV1,
    MintAuthV1,
    MintLimitV1,
    MintLimitOverrideV1,
    Digest
} from "../interface/IST0xOrchestratorV1.sol";

/// @title ST0xOrchestrator
/// @notice Singleton mint/burn proxy for the whole ST0x receipt-vault set.
/// One instance (behind a beacon proxy) serves every token; all per-token
/// state is keyed by the token's `OffchainAssetReceiptVault` address. It
/// holds the vault-side `DEPOSIT` + `WITHDRAW` roles and abstracts receipt
/// handling away from callers — the orchestrator owns every receipt; callers
/// never touch one.
///
/// **Roles** (all administered by `DEFAULT_ADMIN_ROLE`, which itself performs
/// no operations — see the deploy/permissions docs):
///  - `MINT_ROLE` — call `mint`.
///  - `BURN_ROLE` — call `burn`.
///  - `EMERGENCY_ROLE` — recovery ops (`setBurnIndex`, `withdrawReceipt`,
///    `withdrawShares`). Deliberately separate from mint/burn so the key that
///    can reposition pointers or sweep assets can never also mint.
///
/// **Mint recipient authorisation.** `mint` sends shares to an external
/// `to`; to stop a compromised `MINT_ROLE` key from directing freshly minted
/// shares anywhere it likes, every mint must carry the recipient's own
/// authorisation of `(token, to, amount, nonce)` as a `MintAuthV1`: either an
/// EIP-712 signature (verified with `SignatureChecker`, so EOAs sign with
/// ECDSA and contracts via EIP-1271) or, when no signature is supplied, an
/// `IMintRecipient.authorizeMint` callback on `to`. Replay protection is
/// namespaced by recipient: `(to, nonce)` is single-use, regardless of token
/// or amount. The minter's `receiptInformation` audit payload is a separate
/// parameter — it is the MINTER's responsibility and never part of the
/// recipient's authorisation.
///
/// **Vault-logic version lock.** So much of the burn/mint logic depends on
/// the exact behaviour of the current receipt-vault implementation that
/// `initialize` and `mint`/`burn` refuse to run unless the production vault +
/// receipt beacons still point at the implementations this orchestrator was
/// built against (`LibProdDeployCurrent`). If the vault is upgraded, the
/// orchestrator halts until its own implementation is upgraded in lockstep.
/// This mirrors the vault baking the corporate-actions facet address into its
/// own bytecode.
///
/// **Burn walk.** `burn` walks a per-token `nextBurnReceiptId` pointer over
/// the orchestrator's own rebased receipt balances. Burning more than the
/// orchestrator holds reverts `InsufficientReceipts` — a shortfall is an
/// anomaly to recover manually (transfer receipts in, `setBurnIndex`), never
/// papered over by minting fresh receipts. When a production receipt arrives
/// at an id below the pointer with a non-zero balance, the ERC-1155 receiver
/// hook lowers the pointer to it automatically, so transferred-in receipts are
/// always burnable without manual intervention. Zero-value transfers are
/// ignored so the pointer can never be floored over an empty id (see the
/// receiver hooks).
///
/// **Mint caps.** Role membership and the recipient's `MintAuthV1` say WHO
/// may mint and WHERE the shares go; neither bounds HOW MUCH. Every mint is
/// additionally metered by two leaky buckets, and BOTH must accept — this is a
/// conjunction, not most-specific-wins:
///  1. a GLOBAL bucket covering every mint, across all minters and all tokens;
///  2. a per-`(minter, token)` bucket, with its own state per pair, metered
///     against the pair's override if one is set, else `token`'s default.
///
/// So admins configure three things: a global limit, a per-token default, and
/// per-minter overrides per token. All three are `DEFAULT_ADMIN_ROLE` (see
/// `setGlobalMintLimit`, `setTokenMintLimit`, `setMinterMintLimit`,
/// `clearMinterMintLimit`), all emit events, and all are readable.
///
/// **Unset is 0, and 0 fails closed.** An unconfigured limit is `0` and a zero
/// capacity admits nothing. A fresh deployment mints nothing for anyone until
/// a global limit is set; a new token mints nothing until it has a default or
/// the minter has an override. That is deliberate — there is no "nothing
/// configured means unlimited" path anywhere here.
///
/// `capacity` is the burst and `leakRate` is the sustained rate in units per
/// second, both in the same 18-decimal units as `mint`'s `amount` argument
/// (one whole tStock is `1e18`), which is the bucket library's native
/// denomination, so no conversion layer exists. Sizing `capacity` is a
/// security decision: it is the most a compromised minter can take in one go,
/// however long its bucket has been idle.
///
/// All `mint`/`burn` amounts are current rebased tStock units, matching
/// `vault.balanceOf` semantics — so a cap denominated in them meters the
/// rebased unit AS AT the moment of the mint. A corporate action that rebases
/// the unit (e.g. a stock split) therefore rescales what a fixed `capacity` is
/// worth in pre-action terms, and admin must re-set the affected limits
/// alongside the action if the economic size of the cap is meant to hold.
contract ST0xOrchestrator is
    IST0xOrchestratorV1,
    Initializable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardTransient,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;

    bytes32 public constant MINT_ROLE = keccak256("MINT");
    bytes32 public constant BURN_ROLE = keccak256("BURN");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY");

    /// @notice EIP-712 typehash for a recipient's mint authorisation.
    bytes32 public constant MINT_AUTH_TYPEHASH =
        keccak256("MintAuth(address token,address recipient,uint256 amount,bytes32 nonce)");

    /// @custom:storage-location erc7201:st0x.orchestrator.main
    /// @dev The orchestrator is upgradeable behind a beacon, so this struct is
    /// APPEND-ONLY: members are never reordered, removed or retyped, and new
    /// state goes on the end. `nextBurnReceiptId` and `usedNonce` predate the
    /// mint caps and keep their slots.
    struct MainStorage {
        mapping(address token => uint256) nextBurnReceiptId;
        mapping(address to => mapping(bytes32 nonce => bool)) usedNonce;
        /// The policy for the one bucket every mint passes through.
        MintLimitV1 globalMintLimit;
        /// The global bucket itself, as a packed `(level, checkpoint)` word.
        /// A zero word is an empty bucket checkpointed at the epoch, so the
        /// untouched slot needs no initialiser.
        uint256 globalMintBucket;
        /// Per-token DEFAULT policy, used by any minter with no override.
        mapping(address token => MintLimitV1) tokenMintLimit;
        /// Per-`(minter, token)` override of the token default, carrying an
        /// explicit `set` marker so a deliberate zero is expressible.
        mapping(address minter => mapping(address token => MintLimitOverrideV1)) minterMintLimitOverride;
        /// Per-`(minter, token)` bucket state, as packed words. Keyed by the
        /// pair regardless of which policy resolves for it, so the level a
        /// pair has consumed survives an override being set or cleared.
        mapping(address minter => mapping(address token => uint256)) minterMintBucket;
    }

    // keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_LOCATION = 0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    function _main() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_LOCATION
        }
    }

    // Constructor only disables initializers on the implementation; the
    // proxy initialises via `initialize` (OZ upgrades-plugin annotation not
    // used — the repo's Zoltu/beacon deploy path doesn't run that tooling).
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the singleton. Grants `DEFAULT_ADMIN_ROLE` to
    /// `owner` (the owner multisig). Operational roles (`MINT_ROLE`,
    /// `BURN_ROLE`, `EMERGENCY_ROLE`) are granted separately by the admin.
    /// Reverts unless the vault-logic version lock passes, so an orchestrator
    /// can never be initialised against vault logic it wasn't built for.
    /// @param owner Address granted `DEFAULT_ADMIN_ROLE` — the role admin
    /// only; it performs no mint/burn/recovery operations itself.
    function initialize(address owner) external initializer {
        if (owner == address(0)) revert ZeroOwner();
        _checkVaultLogic();
        __AccessControl_init();
        __EIP712_init("ST0xOrchestrator", "1");
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    // ------------------------------------------------------------------ //
    //                       Vault-logic version lock                     //
    // ------------------------------------------------------------------ //

    /// @dev Revert unless the shared production vault + receipt beacons still
    /// point at the implementations pinned in `LibProdDeployCurrent`. Every
    /// production token is a `BeaconProxy` of these two beacons, so this one
    /// check version-locks the orchestrator against every production token at
    /// once. NOTE: it checks the shared beacons, not the specific `token`
    /// argument — a `token` that is NOT a proxy of the shared set is not
    /// covered by the lock. That is not a hazard: such a token has not
    /// granted the orchestrator `DEPOSIT`/`WITHDRAW`, so mint/burn on it
    /// revert at the vault authoriser, and its shares/receipts are its own
    /// (they can never back or drain a real token). The orchestrator is only
    /// ever wired to the production tokens on the shared beacon set.
    modifier onlyExpectedVaultLogic() {
        _checkVaultLogic();
        _;
    }

    function _checkVaultLogic() internal view {
        IST0xVaultBeaconSet beaconSet =
            IST0xVaultBeaconSet(LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        address vaultImpl = beaconSet.iOffchainAssetReceiptVaultBeacon().implementation();
        if (vaultImpl != LibProdDeployCurrent.STOX_RECEIPT_VAULT) {
            revert VaultLogicMismatch(LibProdDeployCurrent.STOX_RECEIPT_VAULT, vaultImpl);
        }
        address receiptImpl = beaconSet.iReceiptBeacon().implementation();
        if (receiptImpl != LibProdDeployCurrent.STOX_RECEIPT) {
            revert ReceiptLogicMismatch(LibProdDeployCurrent.STOX_RECEIPT, receiptImpl);
        }
    }

    /// @inheritdoc IST0xOrchestratorV1
    function vaultLogicIsExpected() external view returns (bool) {
        IST0xVaultBeaconSet beaconSet =
            IST0xVaultBeaconSet(LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        return beaconSet.iOffchainAssetReceiptVaultBeacon().implementation() == LibProdDeployCurrent.STOX_RECEIPT_VAULT
            && beaconSet.iReceiptBeacon().implementation() == LibProdDeployCurrent.STOX_RECEIPT;
    }

    // ------------------------------------------------------------------ //
    //                       Mint / Burn entrypoints                      //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV1
    function mint(
        address token,
        address to,
        uint256 amount,
        MintAuthV1 calldata auth,
        bytes calldata receiptInformation
    ) external onlyRole(MINT_ROLE) onlyExpectedVaultLogic nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _consumeMintCaps(token, amount);
        _consumeMintAuth(token, to, amount, auth);

        // Share ratio is 1:1 by construction; anything else is the vault
        // misbehaving and must halt the mint.
        uint256 assets = OffchainAssetReceiptVault(payable(token)).mint(amount, address(this), 0, receiptInformation);
        if (assets != amount) revert VaultAmountMismatch(amount, assets);
        IERC20(token).safeTransfer(to, amount);
        emit Minted(msg.sender, token, to, amount, auth.nonce);
    }

    /// @dev Meter `amount` through BOTH mint buckets, writing each back, and
    /// revert naming whichever one it did not fit. Runs before the recipient
    /// authorisation so the bucket writes land before any external call, and
    /// so a mint that the caps will refuse never reaches the recipient's
    /// `authorizeMint` callback.
    ///
    /// The global bucket is filled before the per-pair bucket is even checked;
    /// that is safe because a per-pair rejection reverts the whole call, which
    /// unwinds the global fill with it. There is no path that consumes one
    /// bucket without the other.
    ///
    /// `headroomAt` is what `fill` takes — exactly the amount it names fits
    /// and one unit more does not — so the pre-check cannot disagree with the
    /// fill that follows it. It exists only to name WHICH cap bound, which the
    /// library's own `LeakyBucketCapacityExceeded` cannot say.
    function _consumeMintCaps(address token, uint256 amount) internal {
        MainStorage storage $ = _main();

        MintLimitV1 memory globalLimit = $.globalMintLimit;
        uint256 globalBucket = $.globalMintBucket;
        uint256 globalHeadroom = LibLeakyBucketCheckpoint.headroomAt(
            globalBucket, block.timestamp, globalLimit.capacity, globalLimit.leakRate
        );
        if (amount > globalHeadroom) {
            revert GlobalMintCapExceeded(globalLimit.capacity, globalHeadroom, amount);
        }
        $.globalMintBucket = LibLeakyBucketCheckpoint.fill(
            globalBucket, block.timestamp, globalLimit.capacity, globalLimit.leakRate, amount
        );

        MintLimitV1 memory limit = _resolveMintLimit($, msg.sender, token);
        uint256 bucket = $.minterMintBucket[msg.sender][token];
        uint256 headroom = LibLeakyBucketCheckpoint.headroomAt(bucket, block.timestamp, limit.capacity, limit.leakRate);
        if (amount > headroom) {
            revert MinterMintCapExceeded(msg.sender, token, limit.capacity, headroom, amount);
        }
        $.minterMintBucket[msg.sender][token] =
            LibLeakyBucketCheckpoint.fill(bucket, block.timestamp, limit.capacity, limit.leakRate, amount);
    }

    /// @dev The per-pair policy: the `(minter, token)` override if one is set,
    /// else `token`'s default. Both are zero until configured, and a zero
    /// capacity admits nothing, so the fall-through of an unconfigured token
    /// is a closed door rather than an open one.
    function _resolveMintLimit(MainStorage storage $, address minter, address token)
        internal
        view
        returns (MintLimitV1 memory)
    {
        MintLimitOverrideV1 memory pairOverride = $.minterMintLimitOverride[minter][token];
        return pairOverride.set ? pairOverride.limit : $.tokenMintLimit[token];
    }

    /// @dev Consume the recipient's single-use `(to, nonce)` replay slot and
    /// verify the recipient authorised this exact mint. Split out of `mint`
    /// to keep that frame within stack limits.
    function _consumeMintAuth(address token, address to, uint256 amount, MintAuthV1 calldata auth) internal {
        MainStorage storage $ = _main();
        if ($.usedNonce[to][auth.nonce]) revert NonceReplayed(to, auth.nonce);
        $.usedNonce[to][auth.nonce] = true;
        _verifyRecipientAuth(to, _mintAuthDigest(token, to, amount, auth.nonce), auth.signature);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function burn(address token, uint256 amount, bytes calldata burnInfo)
        external
        onlyRole(BURN_ROLE)
        onlyExpectedVaultLogic
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 startIdx = _main().nextBurnReceiptId[token];
        uint256 endIdx = _burnWalk(token, amount, burnInfo);
        emit Burned(msg.sender, token, amount, startIdx, endIdx);
    }

    /// @dev Walk `token`'s pointer, consuming held receipts. Reverts
    /// `InsufficientReceipts` when the walk crosses `highwaterId` with any
    /// amount still unburned — the orchestrator never mints to cover a
    /// shortfall. Persists and returns the final pointer. Split out of
    /// `burn`, and `burnInfo` taken as `memory`, to keep both frames within
    /// stack limits.
    // Pointer write after external calls is safe: every caller holds the
    // ReentrancyGuardTransient lock for the whole entrypoint.
    // slither-disable-next-line reentrancy-no-eth
    function _burnWalk(address token, uint256 remaining, bytes memory burnInfo) internal returns (uint256 idx) {
        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(token));
        IERC1155 vaultReceipt = IERC1155(address(vault.receipt()));
        idx = _main().nextBurnReceiptId[token];
        uint256 cap = vault.highwaterId();
        while (remaining > 0) {
            if (idx > cap) revert InsufficientReceipts(token, remaining);
            // One rebased balanceOf per inspected id is the walk's design.
            // slither-disable-next-line calls-loop
            uint256 bal = vaultReceipt.balanceOf(address(this), idx);
            if (bal == 0) {
                unchecked {
                    idx++;
                }
                continue;
            }
            uint256 take = remaining < bal ? remaining : bal;
            // Share ratio is 1:1 by construction; anything else is the vault
            // misbehaving and must halt the burn.
            // slither-disable-next-line calls-loop
            uint256 assets = vault.redeem(take, address(this), address(this), idx, burnInfo);
            if (assets != take) revert VaultAmountMismatch(take, assets);
            remaining -= take;
            if (take == bal) {
                unchecked {
                    idx++;
                }
            }
        }
        _main().nextBurnReceiptId[token] = idx;
    }

    // ------------------------------------------------------------------ //
    //                          Pointer management                        //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev O(gap) hazard, both directions: set too LOW and the next `burn`
    /// pays one external rebased `balanceOf` per id to cross the gap in a
    /// single tx; set too HIGH and held receipts behind the pointer are
    /// stranded, so burns revert `InsufficientReceipts` once the receipts
    /// ahead of it are exhausted. Set at (or just below) the first id with
    /// non-zero balance. Rarely needed: the receiver hook lowers the pointer
    /// automatically when a receipt arrives below it.
    function setBurnIndex(address token, uint256 newIndex) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        MainStorage storage $ = _main();
        uint256 old = $.nextBurnReceiptId[token];
        $.nextBurnReceiptId[token] = newIndex;
        emit BurnIndexSet(token, old, newIndex);
    }

    // ------------------------------------------------------------------ //
    //                            Mint caps                               //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev Administered by `DEFAULT_ADMIN_ROLE` — the role that administers
    /// `MINT_ROLE` itself. A cap is only as strong as the weakest key that can
    /// raise it, and a separate cap-setting role would be exactly that weaker
    /// key: it could lift the bound on the very mint path it is there to
    /// bound, without being able to grant `MINT_ROLE`. Keeping both under the
    /// one admin means raising a cap is no cheaper than minting the role.
    ///
    /// `checkCapacity` refuses a capacity the bucket codec cannot enforce at
    /// the moment it is WRITTEN, so a misconfiguration surfaces as a refused
    /// governance action rather than as a mint that reverts later.
    function setGlobalMintLimit(uint256 capacity, uint256 leakRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        LibLeakyBucketCheckpoint.checkCapacity(capacity);
        _main().globalMintLimit = MintLimitV1({capacity: capacity, leakRate: leakRate});
        emit GlobalMintLimitSet(capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function setTokenMintLimit(address token, uint256 capacity, uint256 leakRate)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        LibLeakyBucketCheckpoint.checkCapacity(capacity);
        _main().tokenMintLimit[token] = MintLimitV1({capacity: capacity, leakRate: leakRate});
        emit TokenMintLimitSet(token, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function setMinterMintLimit(address minter, address token, uint256 capacity, uint256 leakRate)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        LibLeakyBucketCheckpoint.checkCapacity(capacity);
        _main().minterMintLimitOverride[minter][token] =
            MintLimitOverrideV1({set: true, limit: MintLimitV1({capacity: capacity, leakRate: leakRate})});
        emit MinterMintLimitSet(minter, token, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function clearMinterMintLimit(address minter, address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete _main().minterMintLimitOverride[minter][token];
        emit MinterMintLimitCleared(minter, token);
    }

    // ------------------------------------------------------------------ //
    //                           Emergency sweeps                         //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV1
    function withdrawReceipt(address token, uint256 id, uint256 amount, address to)
        external
        onlyRole(EMERGENCY_ROLE)
        nonReentrant
    {
        IERC1155(address(OffchainAssetReceiptVault(payable(token)).receipt()))
            .safeTransferFrom(address(this), to, id, amount, "");
        emit ReceiptsWithdrawn(token, to, id, amount);
    }

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev The receiver hooks accept all senders (a singleton cannot cheaply
    /// identify every legitimate receipt token up front), so this is the
    /// recovery path for a foreign ERC-1155 that lands here.
    function sweepERC1155(address erc1155, uint256 id, uint256 amount, address to)
        external
        onlyRole(EMERGENCY_ROLE)
        nonReentrant
    {
        IERC1155(erc1155).safeTransferFrom(address(this), to, id, amount, "");
        emit ForeignERC1155Swept(erc1155, to, id, amount);
    }

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev Sweeps tStocks stranded on the orchestrator (sent directly to it,
    /// or rebase-truncation dust after fractional splits).
    function withdrawShares(address token, uint256 amount, address to) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        IERC20(token).safeTransfer(to, amount);
        emit SharesWithdrawn(token, to, amount);
    }

    // ------------------------------------------------------------------ //
    //                              Views                                 //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV1
    function nextBurnReceiptId(address token) external view returns (uint256) {
        return _main().nextBurnReceiptId[token];
    }

    /// @inheritdoc IST0xOrchestratorV1
    function nonceUsed(address to, bytes32 nonce) external view returns (bool) {
        return _main().usedNonce[to][nonce];
    }

    /// @inheritdoc IST0xOrchestratorV1
    function mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) external view returns (Digest) {
        return _mintAuthDigest(token, to, amount, nonce);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function globalMintLimit() external view returns (MintLimitV1 memory) {
        return _main().globalMintLimit;
    }

    /// @inheritdoc IST0xOrchestratorV1
    function tokenMintLimit(address token) external view returns (MintLimitV1 memory) {
        return _main().tokenMintLimit[token];
    }

    /// @inheritdoc IST0xOrchestratorV1
    function minterMintLimitOverride(address minter, address token) external view returns (MintLimitOverrideV1 memory) {
        return _main().minterMintLimitOverride[minter][token];
    }

    /// @inheritdoc IST0xOrchestratorV1
    function mintLimit(address minter, address token) external view returns (MintLimitV1 memory) {
        return _resolveMintLimit(_main(), minter, token);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function mintHeadroom(address minter, address token) external view returns (uint256) {
        MainStorage storage $ = _main();
        MintLimitV1 memory globalLimit = $.globalMintLimit;
        uint256 globalHeadroom = LibLeakyBucketCheckpoint.headroomAt(
            $.globalMintBucket, block.timestamp, globalLimit.capacity, globalLimit.leakRate
        );
        MintLimitV1 memory limit = _resolveMintLimit($, minter, token);
        uint256 pairHeadroom = LibLeakyBucketCheckpoint.headroomAt(
            $.minterMintBucket[minter][token], block.timestamp, limit.capacity, limit.leakRate
        );
        return globalHeadroom < pairHeadroom ? globalHeadroom : pairHeadroom;
    }

    // ------------------------------------------------------------------ //
    //                            Internals                               //
    // ------------------------------------------------------------------ //

    function _mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) internal view returns (Digest) {
        return Digest.wrap(_hashTypedDataV4(keccak256(abi.encode(MINT_AUTH_TYPEHASH, token, to, amount, nonce))));
    }

    /// @dev Verify `to` authorised the mint: an EIP-712 signature (ECDSA or
    /// EIP-1271) when `signature` is non-empty, else an `IMintRecipient`
    /// callback returning the magic selector.
    function _verifyRecipientAuth(address to, Digest digest, bytes memory signature) internal {
        if (signature.length > 0) {
            if (!SignatureChecker.isValidSignatureNow(to, Digest.unwrap(digest), signature)) {
                revert BadRecipientSignature();
            }
        } else {
            if (IMintRecipient(to).authorizeMint(digest) != IMintRecipient.authorizeMint.selector) {
                revert RecipientCallbackRejected(to);
            }
        }
    }

    // ------------------------------------------------------------------ //
    //                          ERC-1155 receiver                         //
    // ------------------------------------------------------------------ //

    /// @dev The hooks accept all senders (a foreign ERC-1155 that lands here
    /// is recoverable via `sweepERC1155`), but when the sender proves to be a
    /// genuine production receipt they self-maintain the burn pointer: a
    /// receipt arriving at an id below `token`'s pointer lowers the pointer
    /// to that id, so transferred-in receipts are always reachable by the
    /// burn walk without any manual `setBurnIndex`.
    ///
    /// The auto-lower only fires for a NON-ZERO transfer. A zero-value
    /// transfer delivers no burnable balance, so lowering the pointer to its
    /// id would only strand the pointer over an empty id: any unprivileged
    /// account could then floor the pointer for free (a zero-value transfer
    /// needs no balance) and inflate the next burn's walk to `O(highwaterId)`,
    /// a repeatable griefing vector. Gating on `value > 0` blocks it while
    /// preserving the intended case — a real receipt transferred in always
    /// carries a non-zero balance.
    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata) external returns (bytes4) {
        if (value > 0) _maybeLowerBurnIndex(msg.sender, id);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata values, bytes calldata)
        external
        returns (bytes4)
    {
        // A genuine ERC-1155 batch always passes equal-length arrays; the
        // `i < values.length` bound only matters for a hand-crafted direct
        // call, which the accept-all hooks must never revert on.
        for (uint256 i = 0; i < ids.length; i++) {
            if (i < values.length && values[i] > 0) _maybeLowerBurnIndex(msg.sender, ids[i]);
        }
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @dev If `erc1155` is a genuine production receipt (its claimed vault
    /// round-trips: `vault.receipt() == erc1155`) and `id` is below that
    /// vault's burn pointer, lower the pointer to `id`. All probes are
    /// defensive raw staticcalls so a foreign or malicious ERC-1155 can never
    /// revert the transfer or spoof a pointer move — spoofing requires
    /// controlling `vault.receipt()`, i.e. already controlling the vault.
    function _maybeLowerBurnIndex(address erc1155, uint256 id) internal {
        // Deliberately raw staticcalls: typed try/catch cannot catch
        // returndata-decode failures, so a malicious ERC-1155 returning
        // garbage could revert the hook and block transfers. Raw calls make
        // the probe unable to revert, preserving accept-all semantics.
        // slither-disable-next-line low-level-calls,calls-loop
        (bool ok, bytes memory ret) = erc1155.staticcall(abi.encodeWithSelector(IReceiptV3.manager.selector));
        if (!ok || ret.length != 32) return;
        // Decoding an address out of 32 bytes of raw returndata: truncating to 160
        // bits IS the decode. `ret.length != 32` is checked above, and a word with
        // dirty high bits simply fails the identity comparison below.
        // forge-lint: disable-next-line(unsafe-typecast)
        address vault = address(uint160(uint256(bytes32(ret))));
        // slither-disable-next-line low-level-calls,calls-loop
        (ok, ret) = vault.staticcall(abi.encodeWithSelector(ReceiptVault.receipt.selector));
        if (!ok || ret.length != 32) return;
        // Decoding an address out of 32 bytes of raw returndata: truncating to 160
        // bits IS the decode. `ret.length != 32` is checked above, and a word with
        // dirty high bits simply fails the identity comparison below.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (address(uint160(uint256(bytes32(ret)))) != erc1155) return;

        MainStorage storage $ = _main();
        uint256 old = $.nextBurnReceiptId[vault];
        if (id < old) {
            $.nextBurnReceiptId[vault] = id;
            emit BurnIndexLowered(vault, old, id);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IST0xOrchestratorV1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @dev `ReceiptVault.mint` is payable and refunds any ETH the vault
    /// holds to `msg.sender` (this orchestrator) via `Address.sendValue` —
    /// always zero in practice. No sweep by design; the orchestrator does
    /// not handle ETH.
    // slither-disable-next-line locked-ether
    receive() external payable {}
}
