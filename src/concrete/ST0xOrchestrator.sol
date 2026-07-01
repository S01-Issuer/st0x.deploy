// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";

/// @title ST0xOrchestrator
/// @notice Per-token mint/burn proxy that sits between the receipt vault and
/// its permissioned callers (any address granted `MINT_BURN_ROLE`). Holds
/// `DEPOSIT` + `WITHDRAW` on the vault's authoriser and abstracts receipt
/// handling away from callers.
///
/// **The orchestrator owns every ERC-1155 receipt.** Callers never touch
/// receipts. `burn` walks a sequential `nextBurnReceiptId` pointer, reading
/// the orchestrator's own rebased receipt balance at each id and consuming
/// them in order. When the walk overshoots `vault.highwaterId()` and still
/// owes burn, it mints a fresh receipt-backed batch to cover the shortfall —
/// letting the orchestrator burn arbitrarily more than it ever minted (the
/// "interest accrued in tStock form" case).
///
/// All amounts in / out of `mint` and `burn` are in **current rebased tStock
/// units**, matching `vault.balanceOf` semantics.
///
/// Deployment: implementation deployed once via Zoltu; per-token instances
/// are `BeaconProxy` clones minted by `ST0xOrchestratorBeaconSetDeployer`,
/// each initialised with its own `(vault, owner)`.
///
/// **No bootstrap on `initialize`.** Receipts are transferred in after
/// deploy (e.g. from a legacy issuer EOA holding pre-existing receipts).
/// After the transfer, an admin calls `setBurnIndex` to point the pointer at
/// the first id with non-zero balance.
contract ST0xOrchestrator is Initializable, AccessControlUpgradeable, IERC1155Receiver {
    using SafeERC20 for IERC20;

    bytes32 public constant MINT_BURN_ROLE = keccak256("MINT_BURN");

    /// @custom:storage-location erc7201:st0x.orchestrator.main
    struct MainStorage {
        OffchainAssetReceiptVault vault;
        IERC1155 receipt;
        uint256 nextBurnReceiptId;
    }

    // keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_LOCATION = 0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    function _main() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_LOCATION
        }
    }

    event Minted(address indexed caller, address indexed to, uint256 amount);
    /// @param firstReceiptId Value of `nextBurnReceiptId` at the *start* of
    /// the call — the first id the walk considered.
    /// @param nextBurnReceiptIdAfter Value of `nextBurnReceiptId` at the
    /// *end* of the call — the id the next `burn` will start scanning from.
    /// This is one past the last id actually consumed when the final iteration
    /// fully drained a receipt; use it as the walk pointer, not as "last
    /// touched id." NOTE: it can be LESS than `firstReceiptId` — when the
    /// pointer was parked beyond `highwaterId + 1` and the shortfall branch
    /// fired, the pointer resets down to the freshly minted id. Indexers must
    /// not assume `[firstReceiptId, nextBurnReceiptIdAfter)` is a consumed
    /// range in that case.
    event Burned(
        address indexed caller,
        address indexed from,
        uint256 amount,
        uint256 firstReceiptId,
        uint256 nextBurnReceiptIdAfter
    );
    /// @notice The burn walk exhausted the orchestrator's held receipts and
    /// minted a fresh receipt-backed batch to cover the shortfall. Fires in
    /// two situations: the documented interest-accrual case (the caller burns
    /// more than the orchestrator ever minted), and rebase-truncation dust
    /// after fractional stock splits (receipt-side truncation is per-id while
    /// share-side truncation is per-account, so held receipt units can total
    /// slightly less than circulating shares). Monitoring should alert when
    /// this fires outside those expectations — e.g. immediately after a
    /// `setBurnIndex` (a mis-set pointer makes every burn 100% shortfall,
    /// silently stranding the pulled shares instead of reducing supply).
    /// @param amount The shortfall covered by the on-demand mint.
    /// @param receiptId The freshly minted receipt id the cover burned from.
    event BurnShortfallMinted(uint256 amount, uint256 receiptId);
    event BurnIndexSet(uint256 oldIndex, uint256 newIndex);
    /// @notice A permissionless `advanceBurnIndex` call skipped the pointer
    /// forward across zero-balance ids (no burn, no admin action).
    event BurnIndexAdvanced(address indexed caller, uint256 oldIndex, uint256 newIndex);
    event ReceiptsWithdrawn(address indexed to, uint256 indexed id, uint256 amount);
    event SharesWithdrawn(address indexed to, uint256 amount);

    /// @notice Initialiser was called with a zero vault address.
    error ZeroVault();
    /// @notice Initialiser was called with a zero owner address.
    error ZeroOwner();
    /// @notice The vault's `receipt()` returned `address(0)`.
    error ZeroReceipt();
    /// @notice `mint` or `burn` was called with a zero amount. Zero mints
    /// revert inside the vault anyway (with a vault-internal error) and zero
    /// burns would emit a phantom `Burned` event that indexers cannot
    /// distinguish from a real burn — reject both up front.
    error ZeroAmount();
    /// @notice An ERC-1155 receiver hook fired from a contract that isn't the
    /// vault's configured receipt token. The transfer is rejected so the
    /// caller keeps the token rather than losing it to a stuck balance here.
    /// @param source The address of the ERC-1155 that tried to transfer here.
    error UnrecognisedERC1155Source(address source);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise a per-token orchestrator clone.
    /// @dev Seeds `nextBurnReceiptId` with `vault_.highwaterId() + 1` — the
    /// first id this orchestrator's own mints can create. Receipt ids below
    /// that belong to other depositors' history; a freshly initialised clone
    /// cannot hold any of them, and scanning them (one external rebased
    /// `balanceOf` per id) would make the first burn on a mature vault cost
    /// O(highwaterId) gas — enough to exceed block gas and wedge the burn
    /// path until an admin repositions the pointer. Receipts transferred in
    /// at lower ids (the documented bootstrap flow, or receipts pre-sent to
    /// a predicted clone address) already require an explicit `setBurnIndex`
    /// to become burnable, which this seeding does not change.
    /// @param vault_ The receipt vault this instance mints and burns against.
    /// Fixed for the lifetime of the clone.
    /// @param owner Address granted `DEFAULT_ADMIN_ROLE`. In production this
    /// is the owner multisig — it holds unilateral authority over
    /// `setBurnIndex`, `withdrawReceipt`, `withdrawShares`, and
    /// `MINT_BURN_ROLE` grants and revocations.
    function initialize(OffchainAssetReceiptVault vault_, address owner) external initializer {
        if (address(vault_) == address(0)) revert ZeroVault();
        if (owner == address(0)) revert ZeroOwner();
        address receipt_ = address(vault_.receipt());
        if (receipt_ == address(0)) revert ZeroReceipt();

        __AccessControl_init();
        MainStorage storage $ = _main();
        $.vault = vault_;
        $.receipt = IERC1155(receipt_);
        $.nextBurnReceiptId = vault_.highwaterId() + 1;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    // ------------------------------------------------------------------ //
    //                              Views                                 //
    // ------------------------------------------------------------------ //

    function vault() external view returns (OffchainAssetReceiptVault) {
        return _main().vault;
    }

    function receipt() external view returns (IERC1155) {
        return _main().receipt;
    }

    function nextBurnReceiptId() external view returns (uint256) {
        return _main().nextBurnReceiptId;
    }

    // ------------------------------------------------------------------ //
    //                       Mint / Burn entrypoints                      //
    // ------------------------------------------------------------------ //

    /// @notice Mint `amount` rebased tStocks to `to` via `vault.mint`. The
    /// fresh ERC-1155 receipt is minted to this orchestrator (kept here
    /// permanently); the share balance is forwarded to `to`.
    /// @dev During a vault certification lapse, only `to == address(this)`
    /// keeps working: the vault's authoriser exempts the mint leg (0 → this)
    /// for `DEPOSIT` holders, but the ERC-20 forward to an external `to` is
    /// an ordinary transfer and reverts `CertificationExpired`. The call is
    /// atomic, so a lapsed-cert external mint reverts cleanly.
    function mint(address to, uint256 amount) external onlyRole(MINT_BURN_ROLE) {
        if (amount == 0) revert ZeroAmount();
        MainStorage storage $ = _main();
        $.vault.mint(amount, address(this), 0, "");
        if (to != address(this)) {
            IERC20(address($.vault)).safeTransfer(to, amount);
        }
        emit Minted(msg.sender, to, amount);
    }

    /// @notice Burn `amount` rebased tStocks from `from`. Pulls the shares
    /// onto the orchestrator (if not already there), then walks the burn
    /// pointer, consuming whatever receipt balances the orchestrator holds
    /// in sequence. Falls back to mint-on-demand when the walk overruns
    /// (emitting `BurnShortfallMinted` so the fallback is observable).
    /// @dev `Burned.amount` is "shares pulled and consumed", NOT the vault
    /// supply delta: any `BurnShortfallMinted` portion nets to zero supply
    /// (fresh mint immediately burned) and strands the equivalent pulled
    /// shares on the orchestrator for the admin `withdrawShares` sweep.
    /// Receipts transferred in at ids below the current pointer are inert
    /// until an admin lowers the pointer via `setBurnIndex` — the walk never
    /// consumes ids below where it started. (The stored pointer CAN decrease
    /// on its own in one case: a pointer parked beyond `highwaterId + 1`
    /// resets down to the freshly minted shortfall id when the fallback
    /// fires — but ids below the walk's start are still never touched.)
    ///
    /// Gas note: each id between the pointer and the burn's completion costs
    /// one external rebased `balanceOf`, including ids minted by OTHER
    /// depositors. The production topology assumes the orchestrator is the
    /// vault's only `DEPOSIT` grantee at steady state; if another minter
    /// coexists (e.g. a legacy issuer EOA during migration), its ids
    /// accumulate one-time scan cost between orchestrator burns — monitor
    /// `vault.highwaterId() - nextBurnReceiptId` and cross large gaps with
    /// `advanceBurnIndex` before they must be crossed inside a burn.
    ///
    /// During a vault certification lapse, only `from == address(this)`
    /// keeps working: the burn leg (this → 0) is exempt for `WITHDRAW`
    /// holders, but the ERC-20 pull from an external `from` is an ordinary
    /// transfer and reverts `CertificationExpired`.
    function burn(address from, uint256 amount) external onlyRole(MINT_BURN_ROLE) {
        if (amount == 0) revert ZeroAmount();
        MainStorage storage $ = _main();
        OffchainAssetReceiptVault vault_ = $.vault;
        IERC1155 receipt_ = $.receipt;

        if (from != address(this)) {
            IERC20(address(vault_)).safeTransferFrom(from, address(this), amount);
        }

        uint256 idx = $.nextBurnReceiptId;
        uint256 startIdx = idx;
        uint256 remaining = amount;
        // Cap the walk at the vault's current highwater. Beyond this id no
        // receipt can possibly exist, so further `balanceOf` calls would
        // walk forever. When we hit the cap and still need to burn, mint
        // a fresh receipt-backed batch to cover the shortfall — net zero
        // supply change (we mint then immediately burn the receipt).
        uint256 cap = vault_.highwaterId();
        while (remaining > 0) {
            if (idx > cap) {
                vault_.mint(remaining, address(this), 0, "");
                cap = vault_.highwaterId();
                idx = cap;
                emit BurnShortfallMinted(remaining, cap);
            }
            uint256 bal = receipt_.balanceOf(address(this), idx);
            if (bal == 0) {
                unchecked {
                    idx++;
                }
                continue;
            }
            uint256 take = remaining < bal ? remaining : bal;
            vault_.redeem(take, address(this), address(this), idx, "");
            remaining -= take;
            if (take == bal) {
                unchecked {
                    idx++;
                }
            }
        }
        $.nextBurnReceiptId = idx;
        emit Burned(msg.sender, from, amount, startIdx, idx);
    }

    // ------------------------------------------------------------------ //
    //                              Admin                                 //
    // ------------------------------------------------------------------ //

    /// @notice Set the burn-walk pointer. Used to bootstrap after receipts
    /// are transferred in (e.g. legacy issuer EOA holdings) and as a
    /// recovery escape hatch if the pointer drifts past valid receipts.
    /// @dev The same O(gap) scan hazard documented on `initialize` applies
    /// here in reverse: parking the pointer below a long run of ids the
    /// orchestrator holds no balance at makes the next `burn` pay one
    /// external rebased `balanceOf` per id to cross the run — all in one
    /// transaction, since burn only persists the pointer on success. Set the
    /// pointer exactly at (or just below) the first id with non-zero
    /// balance, never speculatively low, and after draining transferred-in
    /// receipts re-point past any remaining historical gap (or cross it
    /// incrementally with `advanceBurnIndex`). A pointer set too HIGH is the
    /// opposite failure: every burn becomes 100% mint-on-demand shortfall,
    /// silently stranding pulled shares (see `BurnShortfallMinted`).
    function setBurnIndex(uint256 newIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MainStorage storage $ = _main();
        uint256 old = $.nextBurnReceiptId;
        $.nextBurnReceiptId = newIndex;
        emit BurnIndexSet(old, newIndex);
    }

    /// @notice Walk the burn pointer forward across zero-balance receipt
    /// ids WITHOUT burning, persisting progress. Permissionless: the walk
    /// can only skip ids the orchestrator holds no balance at — it stops at
    /// the first non-zero balance and never passes `vault.highwaterId() + 1`
    /// — so no caller can strand receipts *held at the time of the call* or
    /// misposition the pointer. Receipts arriving later at already-skipped
    /// ids are inert until an admin `setBurnIndex`, exactly as with `burn`'s
    /// own walk — so during a migration, land transfer-ins BEFORE lowering
    /// the pointer beneath their ids.
    ///
    /// Exists because `burn` persists its pointer only on success: a long
    /// zero-balance run (a historical gap below a bootstrap `setBurnIndex`,
    /// or foreign depositors' ids accumulated between orchestrator burns)
    /// must otherwise be crossed inside a single burn transaction, which
    /// can exceed block gas and wedge the burn path. Keepers cross such
    /// gaps incrementally here, bounded by `maxIds` per call.
    /// @param maxIds Maximum ids to inspect in this call.
    /// @return The pointer after advancing.
    function advanceBurnIndex(uint256 maxIds) external returns (uint256) {
        MainStorage storage $ = _main();
        IERC1155 receipt_ = $.receipt;
        uint256 old = $.nextBurnReceiptId;
        uint256 idx = old;
        uint256 cap = $.vault.highwaterId();
        uint256 inspected = 0;
        while (inspected < maxIds && idx <= cap) {
            if (receipt_.balanceOf(address(this), idx) != 0) break;
            unchecked {
                idx++;
                inspected++;
            }
        }
        if (idx != old) {
            $.nextBurnReceiptId = idx;
            emit BurnIndexAdvanced(msg.sender, old, idx);
        }
        return idx;
    }

    /// @notice Escape hatch: pull a specific receipt out of the orchestrator
    /// to a destination address. Use for orphan receipts, migration, or
    /// administrative recovery. Does not affect the burn-walk pointer.
    function withdrawReceipt(uint256 id, uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _main().receipt.safeTransferFrom(address(this), to, id, amount, "");
        emit ReceiptsWithdrawn(to, id, amount);
    }

    /// @notice Escape hatch: pull tStocks out of the orchestrator. Every
    /// interest-accrued repay leaves the interest-amount stranded on the
    /// orchestrator (the mint-on-demand cycle is net zero on balance).
    /// Economically that stranded amount is the issuer's interest income
    /// in tStock form — the issuer EOA sweeps it periodically and burns
    /// via the normal Operator path, releasing the offchain share.
    /// @dev A second, smaller stranding source exists: rebase-truncation
    /// dust. Fractional stock splits truncate receipt balances per-id but
    /// share balances per-account, so after such a split the orchestrator's
    /// total receipt units can be slightly below circulating shares, and the
    /// gap surfaces here via the same mint-on-demand stranding. Sweeps
    /// reconciling "stranded == interest income" should net that dust out.
    function withdrawShares(uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(address(_main().vault)).safeTransfer(to, amount);
        emit SharesWithdrawn(to, amount);
    }

    // ------------------------------------------------------------------ //
    //                          ERC-1155 receiver                         //
    // ------------------------------------------------------------------ //

    /// @dev Only the configured receipt token is a valid sender. Rejecting
    /// unrelated ERC-1155s at the receiver hook keeps them owned by the
    /// original sender rather than trapping them here — `withdrawReceipt`
    /// only recovers tokens on `receipt()`, so a stranded foreign ERC-1155
    /// would be permanently stuck.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(_main().receipt)) revert UnrecognisedERC1155Source(msg.sender);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (msg.sender != address(_main().receipt)) revert UnrecognisedERC1155Source(msg.sender);
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
    /// holds to `msg.sender` (this orchestrator) via `Address.sendValue`.
    /// The refund is always zero in practice — the vault never has an ETH
    /// balance under normal operation. This receiver exists only to keep the
    /// zero-value refund from reverting. There is no sweep function by design:
    /// the orchestrator does not handle ETH, and nothing should ever send it
    /// any.
    receive() external payable {}
}
