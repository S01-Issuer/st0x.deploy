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
    /// touched id."
    event Burned(
        address indexed caller,
        address indexed from,
        uint256 amount,
        uint256 firstReceiptId,
        uint256 nextBurnReceiptIdAfter
    );
    event BurnIndexSet(uint256 oldIndex, uint256 newIndex);
    event ReceiptsWithdrawn(address indexed to, uint256 indexed id, uint256 amount);
    event SharesWithdrawn(address indexed to, uint256 amount);

    /// @notice Initialiser was called with a zero vault address.
    error ZeroVault();
    /// @notice Initialiser was called with a zero owner address.
    error ZeroOwner();
    /// @notice The vault's `receipt()` returned `address(0)`.
    error ZeroReceipt();
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
    function mint(address to, uint256 amount) external onlyRole(MINT_BURN_ROLE) {
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
    /// in sequence. Falls back to mint-on-demand when the walk overruns.
    function burn(address from, uint256 amount) external onlyRole(MINT_BURN_ROLE) {
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
    function setBurnIndex(uint256 newIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MainStorage storage $ = _main();
        uint256 old = $.nextBurnReceiptId;
        $.nextBurnReceiptId = newIndex;
        emit BurnIndexSet(old, newIndex);
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
