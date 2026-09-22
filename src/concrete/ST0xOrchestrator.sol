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

import {
    LibLeakyBucket,
    LeakyBucket,
    LeakyBucketCapacityOverflow
} from "rain-lib-leakybucket-0.4.0/src/lib/LibLeakyBucket.sol";

import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibMintCapUnits} from "../lib/LibMintCapUnits.sol";
import {ICorporateActionsV1} from "../interface/ICorporateActionsV1.sol";
import {IMintRecipient} from "../interface/IMintRecipient.sol";
import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";
import {
    IST0xOrchestratorV1,
    MintAuthV1,
    MintLimitV1,
    MintLimitOverrideV1,
    MintBucketV1,
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
/// **Roles** (administered by `DEFAULT_ADMIN_ROLE`, which itself performs no
/// operations, except that `MINT_ROLE` is administered by `MINT_ADMIN_ROLE` —
/// see the deploy/permissions docs):
///  - `MINT_ADMIN_ROLE` — grant `MINT_ROLE` and set the mint caps.
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
/// **Mint caps.** Every policy is per minter. Every mint is metered by two of
/// the minter's leaky buckets and both must accept: the minter's global bucket
/// across every token, and its per-token bucket metered against the pair's
/// override if one is set, else the minter's default. `MINT_ADMIN_ROLE` sets
/// all three.
///
/// An unconfigured limit is `0` and a zero capacity admits nothing, so a fresh
/// deployment, a new token and a new minter all start unable to mint.
///
/// `capacity` is the burst and `leakRate` the sustained rate per second, in
/// 18-decimal rebased tStock units as at the cursor the limit was set at. A
/// limit stores the numbers that were approved, together with that cursor and
/// its multiplier, and `mint`'s `amount` is converted into the limit's own
/// denomination at metering time. So a rebase rescales what every cap
/// authorises by construction, and nothing is re-set alongside a corporate
/// action. Each bucket carries the denomination its level was consumed in and
/// is converted, never reinterpreted, when it meets a different one.
///
/// The cap setters take the caller's expected `completedActionCount()` and
/// revert if it has moved. Governance is timelocked: an admin approves a
/// figure at one cursor and the transaction executes later, and if an action
/// completes in between the figure no longer means what was approved. That is
/// a revert rather than a silently mispriced cap.
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
    /// @notice Administers `MINT_ROLE` and owns the mint caps. Whoever can
    /// grant the right to mint is who sizes what minting is allowed to do;
    /// splitting those apart would make the cap only as strong as the weaker
    /// of two keys.
    bytes32 public constant MINT_ADMIN_ROLE = keccak256("MINT_ADMIN");
    bytes32 public constant BURN_ROLE = keccak256("BURN");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY");

    /// @notice EIP-712 typehash for a recipient's mint authorisation.
    bytes32 public constant MINT_AUTH_TYPEHASH =
        keccak256("MintAuth(address token,address recipient,uint256 amount,bytes32 nonce)");

    /// @custom:storage-location erc7201:st0x.orchestrator.main
    /// @dev The orchestrator is upgradeable behind a beacon, so this struct is
    /// APPEND-ONLY: members are never reordered, removed or retyped, and new
    /// state goes on the end.
    struct MainStorage {
        mapping(address token => uint256) nextBurnReceiptId;
        mapping(address to => mapping(bytes32 nonce => bool)) usedNonce;
        /// Per-minter global policy, across every token the minter mints, in
        /// the units current at its own cursor.
        mapping(address minter => MintLimitV1) minterGlobalMintLimit;
        /// Per-minter global bucket: a packed `(level, checkpoint)` word plus
        /// the denomination that level is in. A zero multiplier is an unused
        /// bucket.
        mapping(address minter => MintBucketV1) minterGlobalMintBucket;
        /// Per-minter default per-token policy, in the units current at its
        /// own cursor.
        mapping(address minter => MintLimitV1) minterDefaultMintLimit;
        /// Per-`(minter, token)` override of the minter default.
        mapping(address minter => mapping(address token => MintLimitOverrideV1)) minterMintLimitOverride;
        /// Per-`(minter, token)` bucket state, each stamped with the
        /// denomination its level was consumed in. Keyed by the pair
        /// regardless of which policy resolves for it.
        mapping(address minter => mapping(address token => MintBucketV1)) minterMintBucket;
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
        _grantRole(MINT_ADMIN_ROLE, owner);
        _setRoleAdmin(MINT_ROLE, MINT_ADMIN_ROLE);
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

    /// @dev Meter `amount` through both mint buckets, writing each back, and
    /// revert naming whichever one it did not fit. Runs before the recipient
    /// authorisation, so the bucket writes land before any external call.
    ///
    /// The global bucket is filled before the per-pair bucket is checked; a
    /// per-pair rejection reverts the whole call, unwinding that fill with it.
    ///
    /// `headroomAt` is read only to name which cap bound, which the library's
    /// `LeakyBucketCapacityExceeded` cannot say.
    ///
    /// Each limit is denominated at its own cursor, and the two cursors need
    /// not agree, so `amount` is converted once per bucket rather than once
    /// per mint. Dividing by `token`'s multiplier NOW is what neutralises
    /// `token`'s rebase; multiplying by the limit's cursor multiplier is what
    /// states the result in the units the approved number was written in.
    ///
    /// `token` is called once, before any bucket state is read or written.
    function _consumeMintCaps(address token, uint256 amount) internal {
        Float current = ICorporateActionsV1(token).cumulativeBalanceMultiplierSinceGenesis();
        MainStorage storage $ = _main();
        _consumeGlobalMintCap($, amount, current);
        _consumeMinterMintCap($, token, amount, current);
    }

    /// @dev The minter's global bucket, across all tokens. Split out of
    /// `_consumeMintCaps` to keep that frame within stack limits.
    function _consumeGlobalMintCap(MainStorage storage $, uint256 amount, Float current) internal {
        MintLimitV1 memory limit = $.minterGlobalMintLimit[msg.sender];
        if (Float.unwrap(limit.cursorMultiplier) == 0) revert MinterGlobalMintLimitUnset(msg.sender);

        uint256 charge = LibMintCapUnits.redenominateUp(amount, current, limit.cursorMultiplier);
        uint256 checkpoint = _carriedGlobalCheckpoint($, msg.sender, limit.cursorMultiplier);
        uint256 headroom = LibLeakyBucket.headroomAt(_bucket(checkpoint, limit), block.timestamp);
        if (charge > headroom) revert MinterGlobalMintCapExceeded(msg.sender, limit.capacity, headroom, charge);

        $.minterGlobalMintBucket[msg.sender] = MintBucketV1({
            checkpoint: LibLeakyBucket.fill(_bucket(checkpoint, limit), block.timestamp, charge),
            cursorMultiplier: limit.cursorMultiplier
        });
    }

    /// @dev The `(minter, token)` bucket. Reverts unwind the global fill above
    /// it, so there is no path that consumes one bucket without the other.
    function _consumeMinterMintCap(MainStorage storage $, address token, uint256 amount, Float current) internal {
        MintLimitV1 memory limit = _resolveMintLimit($, msg.sender, token);
        if (Float.unwrap(limit.cursorMultiplier) == 0) revert MinterMintLimitUnset(msg.sender, token);

        uint256 charge = LibMintCapUnits.redenominateUp(amount, current, limit.cursorMultiplier);
        uint256 checkpoint = _carriedMinterCheckpoint($, msg.sender, token, limit.cursorMultiplier);
        uint256 headroom = LibLeakyBucket.headroomAt(_bucket(checkpoint, limit), block.timestamp);
        if (charge > headroom) {
            revert MinterMintCapExceeded(msg.sender, token, limit.capacity, headroom, charge);
        }

        $.minterMintBucket[msg.sender][token] = MintBucketV1({
            checkpoint: LibLeakyBucket.fill(_bucket(checkpoint, limit), block.timestamp, charge),
            cursorMultiplier: limit.cursorMultiplier
        });
    }

    /// @dev A checkpoint under a limit, as the library takes it.
    function _bucket(uint256 checkpoint, MintLimitV1 memory limit) internal pure returns (LeakyBucket memory) {
        return LeakyBucket({checkpoint: checkpoint, capacity: limit.capacity, leakRate: limit.leakRate});
    }

    /// @dev A bucket's stored level carried into `to`, or the level itself
    /// when it is already there. A level is always exactly denominated by its
    /// own stamp, so meeting a different denomination converts it; it is never
    /// reinterpreted.
    ///
    /// Rounds UP, for the same reason a charge does: a level rounded down is
    /// headroom handed back that nobody earned.
    ///
    /// A zero level is the same in every denomination and a zero stamp is an
    /// unused bucket, so both pass through untouched — the metering write
    /// restamps them.
    function _carried(MintBucketV1 memory bucket, Float to) internal pure returns (uint256, uint256) {
        if (Float.unwrap(bucket.cursorMultiplier) == 0 || Float.unwrap(bucket.cursorMultiplier) == Float.unwrap(to)) {
            return (bucket.checkpoint, 0);
        }
        (uint256 level, uint256 timestamp) = LibLeakyBucket.unpack(bucket.checkpoint);
        if (level == 0) return (bucket.checkpoint, 0);
        uint256 carried = LibMintCapUnits.redenominateUp(level, bucket.cursorMultiplier, to);
        return (LibLeakyBucket.pack(carried, timestamp), level);
    }

    /// @dev `_carried` for a minter's global bucket, emitting the carry when
    /// one happened. Lazy: a bucket whose policy was re-priced under it
    /// carries itself here, at its next metering, from its own stamp.
    function _carriedGlobalCheckpoint(MainStorage storage $, address minter, Float to) internal returns (uint256) {
        MintBucketV1 memory bucket = $.minterGlobalMintBucket[minter];
        (uint256 checkpoint, uint256 oldLevel) = _carried(bucket, to);
        if (oldLevel != 0) {
            // The timestamp half is deliberately dropped: the event names levels.
            // slither-disable-next-line unused-return
            (uint256 newLevel,) = LibLeakyBucket.unpack(checkpoint);
            emit MinterGlobalMintBucketCarried(minter, oldLevel, newLevel);
        }
        return checkpoint;
    }

    /// @dev `_carried` for a `(minter, token)` bucket. `setMinterDefaultMintLimit`
    /// cannot reach these — one default covers unboundedly many tokens — so
    /// this is where a re-priced default is actually applied to a level.
    function _carriedMinterCheckpoint(MainStorage storage $, address minter, address token, Float to)
        internal
        returns (uint256)
    {
        MintBucketV1 memory bucket = $.minterMintBucket[minter][token];
        (uint256 checkpoint, uint256 oldLevel) = _carried(bucket, to);
        if (oldLevel != 0) {
            // The timestamp half is deliberately dropped: the event names levels.
            // slither-disable-next-line unused-return
            (uint256 newLevel,) = LibLeakyBucket.unpack(checkpoint);
            emit MinterMintBucketCarried(minter, token, oldLevel, newLevel);
        }
        return checkpoint;
    }

    /// @dev Revert unless `token`'s corporate-action cursor is still the one
    /// the caller priced against.
    ///
    /// Every cap setter runs this and stores the multiplier it returns as the
    /// limit's denomination. A moved cursor means the number being written
    /// was approved against units that no longer exist, and the only safe
    /// thing to do with it is refuse to store it.
    function _pinDenomination(address token, uint256 expectedActionCount) internal view returns (Float) {
        uint256 actualActionCount = ICorporateActionsV1(token).completedActionCount();
        if (actualActionCount != expectedActionCount) {
            revert MintLimitCursorMoved(token, expectedActionCount, actualActionCount);
        }
        return ICorporateActionsV1(token).cumulativeBalanceMultiplierSinceGenesis();
    }

    /// @dev The per-pair policy: the `(minter, token)` override if one is set,
    /// else `minter`'s default.
    function _resolveMintLimit(MainStorage storage $, address minter, address token)
        internal
        view
        returns (MintLimitV1 memory)
    {
        MintLimitOverrideV1 memory pairOverride = $.minterMintLimitOverride[minter][token];
        return pairOverride.set ? pairOverride.limit : $.minterDefaultMintLimit[minter];
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
    /// @dev `MINT_ADMIN_ROLE` administers `MINT_ROLE` and owns its caps, so
    /// raising a cap is no cheaper than granting the role it bounds.
    ///
    /// `checkCapacity` refuses a capacity the bucket codec cannot enforce at
    /// the moment it is written.
    ///
    /// The cursor is checked BEFORE the capacity: a cursor that has moved
    /// means the whole set is being re-priced, so naming that rather than a
    /// packing width sends the admin to the right place.
    function setMinterGlobalMintLimit(
        address minter,
        address denominationToken,
        uint256 expectedActionCount,
        uint256 capacity,
        uint256 leakRate
    ) external onlyRole(MINT_ADMIN_ROLE) {
        Float pinned = _pinDenomination(denominationToken, expectedActionCount);
        if (capacity > LibLeakyBucket.LEAKY_BUCKET_LEVEL_MAX) revert LeakyBucketCapacityOverflow(capacity);
        MainStorage storage $ = _main();
        uint256 checkpoint = _carriedGlobalCheckpoint($, minter, pinned);
        $.minterGlobalMintLimit[minter] = MintLimitV1({
            capacity: capacity, leakRate: leakRate, completedActionCount: expectedActionCount, cursorMultiplier: pinned
        });
        $.minterGlobalMintBucket[minter] = MintBucketV1({checkpoint: checkpoint, cursorMultiplier: pinned});
        emit MinterGlobalMintLimitSet(minter, denominationToken, expectedActionCount, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function setMinterDefaultMintLimit(
        address minter,
        address denominationToken,
        uint256 expectedActionCount,
        uint256 capacity,
        uint256 leakRate
    ) external onlyRole(MINT_ADMIN_ROLE) {
        Float pinned = _pinDenomination(denominationToken, expectedActionCount);
        if (capacity > LibLeakyBucket.LEAKY_BUCKET_LEVEL_MAX) revert LeakyBucketCapacityOverflow(capacity);
        _main().minterDefaultMintLimit[minter] = MintLimitV1({
            capacity: capacity, leakRate: leakRate, completedActionCount: expectedActionCount, cursorMultiplier: pinned
        });
        emit MinterDefaultMintLimitSet(minter, denominationToken, expectedActionCount, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function setMinterMintLimit(
        address minter,
        address token,
        uint256 expectedActionCount,
        uint256 capacity,
        uint256 leakRate
    ) external onlyRole(MINT_ADMIN_ROLE) {
        Float pinned = _pinDenomination(token, expectedActionCount);
        if (capacity > LibLeakyBucket.LEAKY_BUCKET_LEVEL_MAX) revert LeakyBucketCapacityOverflow(capacity);
        MainStorage storage $ = _main();
        uint256 checkpoint = _carriedMinterCheckpoint($, minter, token, pinned);
        $.minterMintLimitOverride[minter][token] = MintLimitOverrideV1({
            set: true,
            limit: MintLimitV1({
                capacity: capacity,
                leakRate: leakRate,
                completedActionCount: expectedActionCount,
                cursorMultiplier: pinned
            })
        });
        $.minterMintBucket[minter][token] = MintBucketV1({checkpoint: checkpoint, cursorMultiplier: pinned});
        emit MinterMintLimitSet(minter, token, expectedActionCount, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    function clearMinterMintLimit(address minter, address token) external onlyRole(MINT_ADMIN_ROLE) {
        MainStorage storage $ = _main();
        Float fallbackDenomination = $.minterDefaultMintLimit[minter].cursorMultiplier;
        if (Float.unwrap(fallbackDenomination) != 0) {
            uint256 checkpoint = _carriedMinterCheckpoint($, minter, token, fallbackDenomination);
            $.minterMintBucket[minter][token] =
                MintBucketV1({checkpoint: checkpoint, cursorMultiplier: fallbackDenomination});
        }
        delete $.minterMintLimitOverride[minter][token];
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
    function minterGlobalMintLimit(address minter) external view returns (MintLimitV1 memory) {
        return _main().minterGlobalMintLimit[minter];
    }

    /// @inheritdoc IST0xOrchestratorV1
    function minterDefaultMintLimit(address minter) external view returns (MintLimitV1 memory) {
        return _main().minterDefaultMintLimit[minter];
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
    /// @dev The two limits sit at their own cursors, so their headrooms are in
    /// different units and cannot be compared until both are in current ones.
    /// Each is converted first and the `min` taken after; taking the `min`
    /// first would compare two numbers that do not mean the same thing.
    ///
    /// Zero for an unset limit, matching what a mint would do: an unset limit
    /// admits nothing, and it has no cursor to state a headroom in.
    function mintHeadroom(address minter, address token) external view returns (uint256) {
        MainStorage storage $ = _main();
        Float current = ICorporateActionsV1(token).cumulativeBalanceMultiplierSinceGenesis();

        MintLimitV1 memory globalLimit = $.minterGlobalMintLimit[minter];
        if (Float.unwrap(globalLimit.cursorMultiplier) == 0) return 0;
        MintLimitV1 memory limit = _resolveMintLimit($, minter, token);
        if (Float.unwrap(limit.cursorMultiplier) == 0) return 0;

        (uint256 globalCheckpoint,) = _carried($.minterGlobalMintBucket[minter], globalLimit.cursorMultiplier);
        uint256 globalHeadroom = LibMintCapUnits.redenominateDown(
            LibLeakyBucket.headroomAt(_bucket(globalCheckpoint, globalLimit), block.timestamp),
            globalLimit.cursorMultiplier,
            current
        );

        (uint256 pairCheckpoint,) = _carried($.minterMintBucket[minter][token], limit.cursorMultiplier);
        uint256 pairHeadroom = LibMintCapUnits.redenominateDown(
            LibLeakyBucket.headroomAt(_bucket(pairCheckpoint, limit), block.timestamp), limit.cursorMultiplier, current
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
