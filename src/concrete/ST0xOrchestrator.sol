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

import {LibProdDeployV4} from "../lib/LibProdDeployV4.sol";
import {IMintRecipient} from "../interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";

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
/// authorisation of `(token, to, amount, nonce)`: either an EIP-712
/// signature (verified with `SignatureChecker`, so EOAs sign with ECDSA and
/// contracts via EIP-1271) or, when no signature is supplied, an
/// `IMintRecipient.authorizeMint` callback on `to`. The nonce is single-use
/// (replay-guarded by digest).
///
/// **Vault-logic version lock.** So much of the burn/mint logic depends on
/// the exact behaviour of the current receipt-vault implementation that
/// `mint`/`burn` refuse to run unless the production vault + receipt beacons
/// still point at the implementations this orchestrator was built against
/// (`LibProdDeployV4`). If the vault is upgraded, the orchestrator halts
/// until its own implementation is upgraded in lockstep. This mirrors the
/// vault baking the corporate-actions facet address into its own bytecode.
///
/// **Burn walk.** `burn` walks a per-token `nextBurnReceiptId` pointer over
/// the orchestrator's own rebased receipt balances. Burning more than the
/// orchestrator holds reverts `InsufficientReceipts` — a shortfall is an
/// anomaly to recover manually (transfer receipts in, `setBurnIndex`), never
/// papered over by minting fresh receipts. The pointer is lazily seeded to
/// `highwaterId + 1` on a token's first touch so a fresh token never scans
/// the vault's pre-existing id history; `advanceBurnIndex` crosses
/// accumulated zero-balance gaps incrementally without burning.
///
/// All `mint`/`burn` amounts are current rebased tStock units, matching
/// `vault.balanceOf` semantics.
contract ST0xOrchestrator is
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
    struct MainStorage {
        mapping(address token => uint256) nextBurnReceiptId;
        mapping(address token => bool) tokenSeeded;
        mapping(bytes32 mintAuthDigest => bool) usedMintAuth;
    }

    // keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_LOCATION = 0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    function _main() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_LOCATION
        }
    }

    event Minted(address indexed caller, address indexed token, address indexed to, uint256 amount, bytes32 nonce);
    /// @param firstReceiptId `nextBurnReceiptId[token]` at the start of the call.
    /// @param nextBurnReceiptIdAfter The pointer at the end of the call. The
    /// walk only ever moves forward, so `[firstReceiptId,
    /// nextBurnReceiptIdAfter)` is the consumed id range.
    event Burned(
        address indexed caller,
        address indexed token,
        address indexed from,
        uint256 amount,
        uint256 firstReceiptId,
        uint256 nextBurnReceiptIdAfter
    );
    event BurnIndexSet(address indexed token, uint256 oldIndex, uint256 newIndex);
    event BurnIndexAdvanced(address indexed caller, address indexed token, uint256 oldIndex, uint256 newIndex);
    event TokenSeeded(address indexed token, uint256 pointer);
    event ReceiptsWithdrawn(address indexed token, address indexed to, uint256 indexed id, uint256 amount);
    event SharesWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice A foreign ERC-1155 (not a production receipt) was swept out via
    /// `sweepERC1155`. Distinct from `ReceiptsWithdrawn` so indexers never
    /// mistake `erc1155` for a receipt-vault address.
    event ForeignERC1155Swept(address indexed erc1155, address indexed to, uint256 indexed id, uint256 amount);

    error ZeroOwner();
    error ZeroAmount();
    error MintAuthReplayed(bytes32 digest);
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the singleton. Grants `DEFAULT_ADMIN_ROLE` to
    /// `owner` (the owner multisig). Operational roles (`MINT_ROLE`,
    /// `BURN_ROLE`, `EMERGENCY_ROLE`) are granted separately by the admin.
    /// @param owner Address granted `DEFAULT_ADMIN_ROLE` — the role admin
    /// only; it performs no mint/burn/recovery operations itself.
    function initialize(address owner) external initializer {
        if (owner == address(0)) revert ZeroOwner();
        __AccessControl_init();
        __EIP712_init("ST0xOrchestrator", "1");
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    // ------------------------------------------------------------------ //
    //                       Vault-logic version lock                     //
    // ------------------------------------------------------------------ //

    /// @dev Revert unless the shared production vault + receipt beacons still
    /// point at the implementations pinned in `LibProdDeployV4`. Every
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
        IST0xVaultBeaconSet beaconSet =
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6);
        address vaultImpl = beaconSet.iOffchainAssetReceiptVaultBeacon().implementation();
        if (vaultImpl != LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6) {
            revert VaultLogicMismatch(LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6, vaultImpl);
        }
        address receiptImpl = beaconSet.iReceiptBeacon().implementation();
        if (receiptImpl != LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6) {
            revert ReceiptLogicMismatch(LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6, receiptImpl);
        }
        _;
    }

    /// @notice True if the production vault + receipt beacons currently point
    /// at the implementations this orchestrator expects (i.e. mint/burn are
    /// live rather than version-locked). Offchain convenience.
    function vaultLogicIsExpected() external view returns (bool) {
        IST0xVaultBeaconSet beaconSet =
            IST0xVaultBeaconSet(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6);
        return beaconSet.iOffchainAssetReceiptVaultBeacon().implementation()
                == LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6
            && beaconSet.iReceiptBeacon().implementation() == LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6;
    }

    // ------------------------------------------------------------------ //
    //                       Mint / Burn entrypoints                      //
    // ------------------------------------------------------------------ //

    /// @notice Mint `amount` rebased tStocks of `token` to `to`. The receipt
    /// is minted to (and kept by) the orchestrator; the shares are forwarded
    /// to `to`, which must authorise the mint.
    /// @param token The `OffchainAssetReceiptVault` to mint.
    /// @param to Recipient of the shares. Must authorise via `data`.
    /// @param amount Rebased tStock units to mint.
    /// @param data `abi.encode(bytes signature, bytes32 nonce, bytes
    /// receiptInformation)`. If `signature` is non-empty it is checked
    /// against `to` (ECDSA or EIP-1271) over the EIP-712 digest of
    /// `(token, to, amount, nonce)`; if empty, `IMintRecipient(to)` is
    /// called back. `receiptInformation` is forwarded to `vault.mint` for the
    /// on-chain audit trail.
    function mint(address token, address to, uint256 amount, bytes calldata data)
        external
        onlyRole(MINT_ROLE)
        onlyExpectedVaultLogic
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        (bytes32 nonce, bytes memory receiptInformation) = _consumeMintAuth(token, to, amount, data);

        _seedToken(token);
        OffchainAssetReceiptVault(payable(token)).mint(amount, address(this), 0, receiptInformation);
        IERC20(token).safeTransfer(to, amount);
        emit Minted(msg.sender, token, to, amount, nonce);
    }

    /// @dev Decode `data`, verify + consume the recipient's single-use mint
    /// authorisation, and return `(nonce, receiptInformation)`. Split out of
    /// `mint` to keep that frame within stack limits.
    function _consumeMintAuth(address token, address to, uint256 amount, bytes calldata data)
        internal
        returns (bytes32 nonce, bytes memory receiptInformation)
    {
        bytes memory signature;
        (signature, nonce, receiptInformation) = abi.decode(data, (bytes, bytes32, bytes));
        bytes32 digest = _mintAuthDigest(token, to, amount, nonce);
        MainStorage storage $ = _main();
        if ($.usedMintAuth[digest]) revert MintAuthReplayed(digest);
        $.usedMintAuth[digest] = true;
        _verifyRecipientAuth(to, digest, signature);
    }

    /// @notice Burn `amount` rebased tStocks of `token` from `from`. Pulls
    /// the shares (if not already held), then walks the per-token pointer.
    /// Reverts `InsufficientReceipts` if the orchestrator's held receipts
    /// cannot cover `amount` — recover manually, never by minting.
    /// @param data `receiptInformation` forwarded to `vault.redeem` for the
    /// audit trail — e.g. a tag marking a debt-repay burn.
    function burn(address token, address from, uint256 amount, bytes calldata data)
        external
        onlyRole(BURN_ROLE)
        onlyExpectedVaultLogic
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        _seedToken(token);

        if (from != address(this)) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
        }

        uint256 startIdx = _main().nextBurnReceiptId[token];
        uint256 endIdx = _burnWalk(token, amount, data);
        emit Burned(msg.sender, token, from, amount, startIdx, endIdx);
    }

    /// @dev Walk `token`'s pointer, consuming held receipts. Reverts
    /// `InsufficientReceipts` when the walk crosses `highwaterId` with any
    /// amount still unburned — the orchestrator never mints to cover a
    /// shortfall. Persists and returns the final pointer. Split out of
    /// `burn`, and `data` taken as `memory`, to keep both frames within
    /// stack limits.
    function _burnWalk(address token, uint256 remaining, bytes memory info) internal returns (uint256 idx) {
        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(token));
        IERC1155 receipt_ = IERC1155(address(vault.receipt()));
        idx = _main().nextBurnReceiptId[token];
        uint256 cap = vault.highwaterId();
        while (remaining > 0) {
            if (idx > cap) revert InsufficientReceipts(token, remaining);
            uint256 bal = receipt_.balanceOf(address(this), idx);
            if (bal == 0) {
                unchecked {
                    idx++;
                }
                continue;
            }
            uint256 take = remaining < bal ? remaining : bal;
            vault.redeem(take, address(this), address(this), idx, info);
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

    /// @notice Walk `token`'s burn pointer forward across zero-balance ids
    /// WITHOUT burning, persisting progress. Permissionless: it can only skip
    /// ids the orchestrator holds no balance at, stops at the first non-zero
    /// balance, and never passes `highwaterId + 1` — so no caller can strand
    /// receipts held at call time or misposition the pointer. Lets keepers
    /// cross a long zero-balance gap incrementally (bounded by `maxIds`)
    /// instead of forcing a single burn to cross it and risk out-of-gas.
    /// Receipts arriving later at already-skipped ids are inert until an
    /// `EMERGENCY_ROLE` `setBurnIndex`, as with `burn`.
    function advanceBurnIndex(address token, uint256 maxIds)
        external
        onlyExpectedVaultLogic
        nonReentrant
        returns (uint256)
    {
        _seedToken(token);
        MainStorage storage $ = _main();
        IERC1155 receipt_ = IERC1155(address(OffchainAssetReceiptVault(payable(token)).receipt()));
        uint256 old = $.nextBurnReceiptId[token];
        uint256 idx = old;
        uint256 cap = OffchainAssetReceiptVault(payable(token)).highwaterId();
        uint256 inspected = 0;
        while (inspected < maxIds && idx <= cap) {
            if (receipt_.balanceOf(address(this), idx) != 0) break;
            unchecked {
                idx++;
                inspected++;
            }
        }
        if (idx != old) {
            $.nextBurnReceiptId[token] = idx;
            emit BurnIndexAdvanced(msg.sender, token, old, idx);
        }
        return idx;
    }

    /// @notice `EMERGENCY_ROLE` override of `token`'s burn pointer — bootstrap
    /// after receipts are transferred in, or recover from a mis-set pointer.
    /// @dev O(gap) hazard, both directions: set too LOW and the next `burn`
    /// pays one external rebased `balanceOf` per id to cross the gap in a
    /// single tx (mitigate with `advanceBurnIndex`); set too HIGH and held
    /// receipts behind the pointer are stranded, so burns revert
    /// `InsufficientReceipts` once the receipts ahead of it are exhausted.
    /// Set at (or just below) the first id with non-zero balance.
    function setBurnIndex(address token, uint256 newIndex) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        MainStorage storage $ = _main();
        $.tokenSeeded[token] = true;
        uint256 old = $.nextBurnReceiptId[token];
        $.nextBurnReceiptId[token] = newIndex;
        emit BurnIndexSet(token, old, newIndex);
    }

    // ------------------------------------------------------------------ //
    //                           Emergency sweeps                         //
    // ------------------------------------------------------------------ //

    /// @notice `EMERGENCY_ROLE` escape hatch: pull a specific receipt out.
    function withdrawReceipt(address token, uint256 id, uint256 amount, address to) external onlyRole(EMERGENCY_ROLE) {
        IERC1155(address(OffchainAssetReceiptVault(payable(token)).receipt()))
            .safeTransferFrom(address(this), to, id, amount, "");
        emit ReceiptsWithdrawn(token, to, id, amount);
    }

    /// @notice `EMERGENCY_ROLE` escape hatch: rescue any ERC-1155 stuck on
    /// the orchestrator. The receiver hooks accept all senders (a singleton
    /// cannot cheaply identify every legitimate receipt token up front), so
    /// this is the recovery path for a foreign ERC-1155 that lands here.
    function sweepERC1155(address erc1155, uint256 id, uint256 amount, address to)
        external
        onlyRole(EMERGENCY_ROLE)
        nonReentrant
    {
        IERC1155(erc1155).safeTransferFrom(address(this), to, id, amount, "");
        emit ForeignERC1155Swept(erc1155, to, id, amount);
    }

    /// @notice `EMERGENCY_ROLE` escape hatch: sweep tStocks stranded on the
    /// orchestrator (sent directly to it, or rebase-truncation dust after
    /// fractional splits).
    function withdrawShares(address token, uint256 amount, address to) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        IERC20(token).safeTransfer(to, amount);
        emit SharesWithdrawn(token, to, amount);
    }

    // ------------------------------------------------------------------ //
    //                              Views                                 //
    // ------------------------------------------------------------------ //

    function nextBurnReceiptId(address token) external view returns (uint256) {
        return _main().nextBurnReceiptId[token];
    }

    function tokenSeeded(address token) external view returns (bool) {
        return _main().tokenSeeded[token];
    }

    function mintAuthUsed(bytes32 digest) external view returns (bool) {
        return _main().usedMintAuth[digest];
    }

    /// @notice The EIP-712 digest a recipient signs (or checks in its
    /// `authorizeMint` callback) to authorise a mint.
    function mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) external view returns (bytes32) {
        return _mintAuthDigest(token, to, amount, nonce);
    }

    // ------------------------------------------------------------------ //
    //                            Internals                               //
    // ------------------------------------------------------------------ //

    function _mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(MINT_AUTH_TYPEHASH, token, to, amount, nonce)));
    }

    /// @dev Verify `to` authorised the mint: an EIP-712 signature (ECDSA or
    /// EIP-1271) when `signature` is non-empty, else an `IMintRecipient`
    /// callback returning the magic selector.
    function _verifyRecipientAuth(address to, bytes32 digest, bytes memory signature) internal {
        if (signature.length > 0) {
            if (!SignatureChecker.isValidSignatureNow(to, digest, signature)) revert BadRecipientSignature();
        } else {
            if (IMintRecipient(to).authorizeMint(digest) != IMintRecipient.authorizeMint.selector) {
                revert RecipientCallbackRejected(to);
            }
        }
    }

    /// @dev Lazily seed a token's burn pointer to `highwaterId + 1` on first
    /// touch, so a fresh token never scans the vault's pre-existing id
    /// history. Bootstraps of transferred-in receipts at lower ids use an
    /// `EMERGENCY_ROLE` `setBurnIndex` afterwards.
    function _seedToken(address token) internal {
        MainStorage storage $ = _main();
        if ($.tokenSeeded[token]) return;
        $.tokenSeeded[token] = true;
        uint256 seeded = OffchainAssetReceiptVault(payable(token)).highwaterId() + 1;
        $.nextBurnReceiptId[token] = seeded;
        emit TokenSeeded(token, seeded);
    }

    // ------------------------------------------------------------------ //
    //                          ERC-1155 receiver                         //
    // ------------------------------------------------------------------ //

    /// @dev A singleton cannot cheaply identify every legitimate receipt
    /// token at callback time (each token has its own receipt, and a
    /// `BeaconProxy`'s beacon is not externally readable), so the hooks
    /// accept all senders. This is safe: the orchestrator only credits its
    /// burn walk against receipts its OWN `vault.mint` created, and any
    /// foreign ERC-1155 that lands here is recoverable via `sweepERC1155`.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev `ReceiptVault.mint` is payable and refunds any ETH the vault
    /// holds to `msg.sender` (this orchestrator) via `Address.sendValue` —
    /// always zero in practice. No sweep by design; the orchestrator does
    /// not handle ETH.
    receive() external payable {}
}
