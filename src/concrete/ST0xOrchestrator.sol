// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.7.0/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.7.0/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts-5.7.0/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin-contracts-5.7.0/utils/introspection/IERC165.sol";
import {SignatureChecker} from "@openzeppelin-contracts-5.7.0/utils/cryptography/SignatureChecker.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.2.18/src/abstract/OffchainAssetReceiptVault.sol";
import {IReceiptV3} from "rain-vats-0.2.18/src/interface/IReceiptV3.sol";
import {ReceiptVault} from "rain-vats-0.2.18/src/abstract/ReceiptVault.sol";

import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {LibLeakyBucket, LeakyBucket} from "rain-lib-leakybucket-0.5.3/src/lib/LibLeakyBucket.sol";
import {LibTOFUTokenDecimals} from "rain-tofu-erc20-decimals-0.1.4/src/lib/LibTOFUTokenDecimals.sol";
import {LibIntOrAString, IntOrAString, LENGTH_MASK_V3} from "rain-intorastring-0.1.4/src/lib/LibIntOrAString.sol";
import {
    IInterpreterCallerV5,
    EvaluableV4,
    SignedContextV2
} from "rainlang-0.2.32/src/interface/IInterpreterCallerV5.sol";
import {
    EvalV4,
    SourceIndexV2,
    StackItem,
    StateNamespace,
    DEFAULT_STATE_NAMESPACE
} from "rainlang-0.2.32/src/interface/IInterpreterV4.sol";
import {LibNamespace} from "rainlang-0.2.32/src/lib/ns/LibNamespace.sol";

import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {IMintRecipient} from "../interface/IMintRecipient.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {LibExtrospectRegistryBeaconProxy} from "rain-extrospection-0.1.16/src/lib/LibExtrospectRegistryBeaconProxy.sol";
import {IST0xOrchestratorV2, MintAuthV1, MintLimitV1, MintCapKind, Digest} from "../interface/IST0xOrchestratorV2.sol";
import {LibSt0xAttestContext} from "../lib/LibSt0xAttestContext.sol";
import {LibStoxConfig} from "../lib/LibStoxConfig.sol";
import {ICLONEABLE_V2_SUCCESS, ICloneableV2} from "rain-factory-0.2.10/src/interface/ICloneableV2.sol";

/// @dev The orchestrator's role ids at file level, so a library can name them:
/// a contract's `public constant` is not reachable as `ST0xOrchestrator.X`.
/// `ST0xOrchestrator` exposes each as its `*_ROLE` getter.
bytes32 constant ORCHESTRATOR_MINT_ROLE = keccak256("MINT");
bytes32 constant ORCHESTRATOR_MINT_ADMIN_ROLE = keccak256("MINT_ADMIN");
bytes32 constant ORCHESTRATOR_BURN_ROLE = keccak256("BURN");
bytes32 constant ORCHESTRATOR_BURN_ADMIN_ROLE = keccak256("BURN_ADMIN");
bytes32 constant ORCHESTRATOR_EMERGENCY_ROLE = keccak256("EMERGENCY");
bytes32 constant ORCHESTRATOR_EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN");

/// @title ST0xOrchestrator
/// @notice Singleton mint/burn proxy for the ST0x receipt-vault set. One
/// instance (behind a registry beacon proxy) serves every token; all per-token state
/// is keyed by the token's `OffchainAssetReceiptVault` address. It holds the
/// vault-side `DEPOSIT` + `WITHDRAW` roles and owns every receipt; callers
/// never touch one.
///
/// **Roles.** Every role that does something has its own admin role, and each
/// admin role administers both its operating role and itself (see
/// `initialize`). `DEFAULT_ADMIN_ROLE` administers none of them and performs
/// no operations at all.
///  - `MINT_ADMIN_ROLE` — grant `MINT_ROLE` and `MINT_ADMIN_ROLE`, set the mint
///    caps and the mint weighting.
///  - `MINT_ROLE` — call `mint`.
///  - `BURN_ADMIN_ROLE` — grant `BURN_ROLE` and `BURN_ADMIN_ROLE`. The burn side
///    has no policy to set, so that is the whole of it.
///  - `BURN_ROLE` — call `burn`.
///  - `EMERGENCY_ADMIN_ROLE` — grant `EMERGENCY_ROLE` and
///    `EMERGENCY_ADMIN_ROLE`, and nothing else. Saying who may hold the
///    recovery key is not holding it.
///  - `EMERGENCY_ROLE` — recovery ops (`setBurnIndex`, `withdrawReceipt`,
///    `withdrawShares`, `sweepERC1155`). Deliberately separate from
///    mint/burn, so the key that can reposition pointers or sweep assets can
///    never also mint.
///
/// An admin role is held separately from the role it administers: granting
/// `MINT_ADMIN_ROLE` does not grant `MINT_ROLE`, and `initialize` grants only
/// the admin roles.
///
/// **Custody.** `initialize` seats `DEFAULT_ADMIN_ROLE` and the three admin
/// roles on the account the root authority binds in the `ConfigRegistry` under
/// `LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME`. No operating role is held
/// until an admin grants it.
///
/// **Mint recipient authorisation.** Every mint carries the recipient's own
/// authorisation of `(token, to, amount, nonce)` as a `MintAuthV1`: either an
/// EIP-712 signature (verified with `SignatureChecker`, so EOAs sign with
/// ECDSA and contracts via EIP-1271) or, when no signature is supplied, an
/// `IMintRecipient.authorizeMint` callback on `to`. Replay protection is
/// namespaced by recipient: `(to, nonce)` is single-use, regardless of token
/// or amount. The minter's `receiptInformation` payload is a separate
/// parameter and never part of the recipient's authorisation. `to ==
/// msg.sender` reverts `SenderIsRecipient`, with no override.
///
/// **Vault-logic version lock.** So much of the burn/mint logic depends on
/// the exact behaviour of the current receipt-vault implementation that
/// `mint`/`burn` refuse to run unless the token and its receipt are registry
/// beacon proxies whose own beacons serve the implementations this
/// orchestrator was built against (`LibProdDeployCurrent`). If the vault is
/// upgraded, the orchestrator halts until its own implementation is upgraded
/// in lockstep. This mirrors the vault baking the corporate-actions facet
/// address into its own bytecode.
///
/// **Burn walk.** `burn` walks a per-token `nextBurnReceiptId` pointer over
/// the orchestrator's own rebased receipt balances. Burning more than the
/// orchestrator holds reverts `InsufficientReceipts`; the orchestrator never
/// mints to cover a shortfall. When a production receipt arrives at an id
/// below the pointer with a non-zero balance, the ERC-1155 receiver hook
/// lowers the pointer to it. Zero-value transfers are ignored.
///
/// **Mint caps.** Every mint is metered by the minter's leaky bucket and the
/// recipient's, and both must accept. The minter's bucket is global across
/// every token and recipient it mints to; the recipient's is global across
/// every token and minter it is minted by. Nothing is metered per token.
/// `MINT_ADMIN_ROLE` sets both policies, each a `capacity` and a `leakRate`.
/// An unset limit admits nothing.
///
/// Every number in a cap is a Rain `Float`: `capacity` is the burst and
/// `leakRate` the sustained rate per second. What a mint is charged is the
/// value the mint weighting puts on it, never the token amount. The cap path
/// never reads the token's corporate-action state.
///
/// **Mint weighting.** One Rainlang expression, set by `MINT_ADMIN_ROLE` and
/// global across every token, minter and recipient, converts each mint into
/// the charge. `mint` builds the context grid of `LibSt0xAttestContext` (the
/// token's symbol, the amount as a `Float` of whole tokens, then the signed
/// context the minter passed, every signature verified) and evaluates the
/// expression over it. The last output is the charge on both buckets. What
/// the signed context must contain is the expression's to check and revert
/// on; the orchestrator verifies only that each entry was signed by the
/// signer it names under the domain separator it names. State the
/// expression writes is persisted to its store under the orchestrator's
/// namespace.
///
/// The bucket library refuses a zero charge and a negative charge at every
/// fill. A weighting that evaluates to zero or below is a refused mint.
contract ST0xOrchestrator is
    IST0xOrchestratorV2,
    IInterpreterCallerV5,
    ICloneableV2,
    Initializable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardTransient,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;
    using LibDecimalFloat for Float;

    bytes32 public constant MINT_ROLE = ORCHESTRATOR_MINT_ROLE;
    /// @notice Administers `MINT_ROLE` and sets the mint caps and the mint
    /// weighting.
    bytes32 public constant MINT_ADMIN_ROLE = ORCHESTRATOR_MINT_ADMIN_ROLE;
    bytes32 public constant BURN_ROLE = ORCHESTRATOR_BURN_ROLE;
    /// @notice Administers `BURN_ROLE`. The burn side carries no policy to
    /// set, so granting and revoking `BURN_ROLE` is all this role does — the
    /// burn-pointer repair is `EMERGENCY_ROLE`'s, deliberately apart from
    /// both.
    bytes32 public constant BURN_ADMIN_ROLE = ORCHESTRATOR_BURN_ADMIN_ROLE;
    bytes32 public constant EMERGENCY_ROLE = ORCHESTRATOR_EMERGENCY_ROLE;
    /// @notice Administers `EMERGENCY_ROLE`. Holding this is not holding
    /// `EMERGENCY_ROLE`: it says who may be handed the recovery key, never
    /// that its holder may turn it.
    bytes32 public constant EMERGENCY_ADMIN_ROLE = ORCHESTRATOR_EMERGENCY_ADMIN_ROLE;
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
        mapping(MintCapKind kind => mapping(address account => MintCapV1)) mintCaps;
        /// The mint weighting: the one expression that converts every mint
        /// into the charge on both buckets. A zero interpreter is unset.
        EvaluableV4 mintWeighting;
    }

    /// @dev One cap. Live storage holds the members in this order; they are
    /// never reordered.
    /// @param bucket The bucket and its policy, as `LibLeakyBucket` stores it.
    /// @param set True once a limit has been written (see `MintLimitV1`).
    struct MintCapV1 {
        LeakyBucket bucket;
        bool set;
    }

    // keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_LOCATION = 0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    /// @dev The mint weighting is evaluated as the first source of its
    /// bytecode.
    SourceIndexV2 private constant MINT_WEIGHTING_ENTRYPOINT = SourceIndexV2.wrap(0);

    /// @dev The mint weighting must leave at least this many outputs; the
    /// last is the charge.
    uint256 private constant MINT_WEIGHTING_MIN_OUTPUTS = 1;

    /// @dev The one expression has one namespace in its store. The store
    /// qualifies it with the orchestrator's address on every write, and the
    /// orchestrator qualifies it the same way for every read, so nothing
    /// another caller of the same store writes can be read here.
    StateNamespace private constant MINT_WEIGHTING_NAMESPACE = DEFAULT_STATE_NAMESPACE;

    function _main() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_LOCATION
        }
    }

    // Only the proxy is initialised, via `initialize`.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the singleton. Grants the initial admin
    /// `DEFAULT_ADMIN_ROLE`, `MINT_ADMIN_ROLE`, `BURN_ADMIN_ROLE` and
    /// `EMERGENCY_ADMIN_ROLE`, then delegates each operating role to its own
    /// admin. `MINT_ROLE`, `BURN_ROLE` and `EMERGENCY_ROLE` are granted
    /// separately. Reverts when the root authority has not bound
    /// `LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME` as an `address`.
    ///
    /// @dev The initial admin is resolved from the `ConfigRegistry` rather than
    /// taken as an argument, so whoever creates the registry beacon proxy
    /// cannot seat an admin of its own. `data` is unused.
    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata) external initializer returns (bytes32) {
        address admin = LibStoxConfig.orchestratorInitialAdmin();
        __AccessControl_init();
        __EIP712_init("ST0xOrchestrator", "1");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // Self-administering admin roles seat, rotate and revoke peers without the root.
        _setRoleAdmin(MINT_ROLE, MINT_ADMIN_ROLE);
        _setRoleAdmin(MINT_ADMIN_ROLE, MINT_ADMIN_ROLE);
        _grantRole(MINT_ADMIN_ROLE, admin);

        _setRoleAdmin(BURN_ROLE, BURN_ADMIN_ROLE);
        _setRoleAdmin(BURN_ADMIN_ROLE, BURN_ADMIN_ROLE);
        _grantRole(BURN_ADMIN_ROLE, admin);

        _setRoleAdmin(EMERGENCY_ROLE, EMERGENCY_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ADMIN_ROLE, EMERGENCY_ADMIN_ROLE);
        _grantRole(EMERGENCY_ADMIN_ROLE, admin);

        return ICLONEABLE_V2_SUCCESS;
    }

    // ------------------------------------------------------------------ //
    //                       Vault-logic version lock                     //
    // ------------------------------------------------------------------ //

    modifier onlyExpectedVaultLogic(address token) {
        _checkVaultLogic(token);
        _;
    }

    /// The implementation served by the beacon in `proxy`'s registry beacon
    /// proxy bytecode, or false when `proxy` has other code.
    function _beaconImplementation(address proxy) internal view returns (bool, address) {
        (bool isProxy, address beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(proxy.code);
        return (isProxy, isProxy ? IBeacon(beacon).implementation() : address(0));
    }

    function _checkVaultLogic(address token) internal view {
        (bool isProxy, address vaultImpl) = _beaconImplementation(token);
        if (!isProxy) revert NotRegistryBeaconProxy(token);
        if (vaultImpl != LibProdDeployCurrent.STOX_RECEIPT_VAULT) {
            revert VaultLogicMismatch(LibProdDeployCurrent.STOX_RECEIPT_VAULT, vaultImpl);
        }
        address receipt = address(ReceiptVault(payable(token)).receipt());
        address receiptImpl;
        (isProxy, receiptImpl) = _beaconImplementation(receipt);
        if (!isProxy) revert NotRegistryBeaconProxy(receipt);
        if (receiptImpl != LibProdDeployCurrent.STOX_RECEIPT) {
            revert ReceiptLogicMismatch(LibProdDeployCurrent.STOX_RECEIPT, receiptImpl);
        }
    }

    /// @inheritdoc IST0xOrchestratorV2
    function vaultLogicIsExpected(address token) external view returns (bool) {
        // A non-proxy yields address(0), which is never an expected implementation.
        (, address impl) = _beaconImplementation(token);
        if (impl != LibProdDeployCurrent.STOX_RECEIPT_VAULT) return false;
        (, impl) = _beaconImplementation(address(ReceiptVault(payable(token)).receipt()));
        return impl == LibProdDeployCurrent.STOX_RECEIPT;
    }

    // ------------------------------------------------------------------ //
    //                       Mint / Burn entrypoints                      //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV2
    // The nonce write follows external calls under the entrypoint's `nonReentrant` lock.
    // slither-disable-next-line reentrancy-no-eth
    function mint(
        address token,
        address to,
        uint256 amount,
        MintAuthV1 calldata auth,
        bytes calldata receiptInformation,
        SignedContextV2[] calldata signedContext
    ) external onlyRole(MINT_ROLE) onlyExpectedVaultLogic(token) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (to == msg.sender) revert SenderIsRecipient(msg.sender);
        _consumeMintCaps(token, to, amount, signedContext);
        _consumeMintAuth(token, to, amount, auth);

        // Share ratio is 1:1; anything else halts the mint.
        uint256 assets = OffchainAssetReceiptVault(payable(token)).mint(amount, address(this), 0, receiptInformation);
        if (assets != amount) revert VaultAmountMismatch(amount, assets);
        IERC20(token).safeTransfer(to, amount);
        emit Minted(msg.sender, token, to, amount, auth.nonce);
    }

    /// @dev Put a value on the mint with the mint weighting, then meter that
    /// value through both mint buckets, writing each back, and revert naming
    /// whichever one it did not fit. Runs before the recipient authorisation,
    /// so the bucket writes land before the callback to `to`.
    ///
    /// Both limits are checked for having been set before the weighting is
    /// evaluated: an unset limit is refused without verifying a signature or
    /// calling an interpreter.
    ///
    /// The minter's bucket is filled before the recipient's is checked; a
    /// recipient rejection reverts the whole call.
    ///
    /// `headroomAt` is read to name which cap bound.
    function _consumeMintCaps(address token, address to, uint256 amount, SignedContextV2[] calldata signedContext)
        internal
    {
        MainStorage storage $ = _main();
        MintCapV1 storage minterCap = $.mintCaps[MintCapKind.Minter][msg.sender];
        MintCapV1 storage recipientCap = $.mintCaps[MintCapKind.Recipient][to];
        if (!minterCap.set) revert MintLimitUnset(MintCapKind.Minter, msg.sender);
        if (!recipientCap.set) revert MintLimitUnset(MintCapKind.Recipient, to);

        // The buckets meter the weighted charge, never the raw amount.
        Float charge = _weighMint($, token, amount, signedContext);
        Float timestamp = _now();
        _fillMintCap(minterCap, MintCapKind.Minter, msg.sender, timestamp, charge);
        _fillMintCap(recipientCap, MintCapKind.Recipient, to, timestamp, charge);
    }

    /// @dev Evaluate the mint weighting over this mint and its signed context
    /// and return the charge. Reverts `MintWeightingUnset` if no expression
    /// has been set, `MintSymbolTooLong` if the token's symbol is longer
    /// than the 31 bytes an `IntOrAString` holds,
    /// `UnsupportedMintWeightingOutputs` if the expression left nothing on its
    /// stack, and with whatever the expression itself reverts with.
    ///
    /// The context is the grid of `LibSt0xAttestContext`: the token's symbol
    /// as an `IntOrAString`, and the amount as a `Float` in whole tokens per
    /// the token's decimals as the TOFU singleton first read them. Building the grid verifies every
    /// signed context entry's signature and reverts `InvalidSignature(i)` on the first
    /// that fails.
    ///
    /// The evaluation is a static call; the writes it returns are then
    /// applied to the expression's store under the orchestrator's namespace.
    /// Split out of `_consumeMintCaps` to keep that frame within stack limits.
    function _weighMint(MainStorage storage $, address token, uint256 amount, SignedContextV2[] calldata signedContext)
        internal
        returns (Float)
    {
        EvaluableV4 memory evaluable = $.mintWeighting;
        if (address(evaluable.interpreter) == address(0)) revert MintWeightingUnset();

        string memory symbol = IERC20Metadata(token).symbol();
        // `fromStringV3` keeps the length mod 32, so a longer symbol would alias a shorter one.
        if (bytes(symbol).length > LENGTH_MASK_V3) revert MintSymbolTooLong(token, bytes(symbol).length);
        uint8 decimals = LibTOFUTokenDecimals.safeDecimalsForToken(token);
        bytes32[][] memory context = LibSt0xAttestContext.build(
            bytes32(IntOrAString.unwrap(LibIntOrAString.fromStringV3(symbol))),
            Float.unwrap(LibDecimalFloat.fromFixedDecimalLosslessPacked(amount, decimals)),
            signedContext
        );
        emit ContextV2(msg.sender, context);

        (StackItem[] memory stack, bytes32[] memory writes) = evaluable.interpreter
            .eval4(
                EvalV4({
                    store: evaluable.store,
                    namespace: LibNamespace.qualifyNamespace(MINT_WEIGHTING_NAMESPACE, address(this)),
                    bytecode: evaluable.bytecode,
                    sourceIndex: MINT_WEIGHTING_ENTRYPOINT,
                    context: context,
                    inputs: new StackItem[](0),
                    stateOverlay: new bytes32[](0)
                })
            );
        if (stack.length < MINT_WEIGHTING_MIN_OUTPUTS) revert UnsupportedMintWeightingOutputs(stack.length);
        if (writes.length > 0) {
            evaluable.store.set(MINT_WEIGHTING_NAMESPACE, writes);
        }
        // The stack top, the expression's last output, is item zero.
        return Float.wrap(StackItem.unwrap(stack[0]));
    }

    /// @dev Fill `account`'s `kind` bucket with `charge`, reverting
    /// `MintCapExceeded` when it does not fit. Split out of `_consumeMintCaps`
    /// to keep that frame within stack limits.
    // The bucket write follows external calls under the entrypoint's `nonReentrant` lock.
    // slither-disable-next-line reentrancy-no-eth
    function _fillMintCap(MintCapV1 storage cap, MintCapKind kind, address account, Float timestamp, Float charge)
        internal
    {
        LeakyBucket memory bucket = cap.bucket;
        Float headroom = LibLeakyBucket.headroomAt(bucket, timestamp);
        if (charge.gt(headroom)) revert MintCapExceeded(kind, account, bucket.capacity, headroom, charge);

        (cap.bucket.level, cap.bucket.timestamp) = LibLeakyBucket.fill(bucket, timestamp, charge);
    }

    /// @dev `block.timestamp` as the library's clock: seconds, at exponent
    /// zero, so `leakRate` is per second.
    function _now() internal view returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(block.timestamp, 0);
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

    /// @inheritdoc IST0xOrchestratorV2
    function burn(address token, uint256 amount, bytes calldata burnInfo)
        external
        onlyRole(BURN_ROLE)
        onlyExpectedVaultLogic(token)
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
    /// amount still unburned. Persists and returns the final pointer. Split
    /// out of `burn`, and `burnInfo` taken as `memory`, to keep both frames
    /// within stack limits.
    // The pointer write follows external calls under the entrypoint's `nonReentrant` lock.
    // slither-disable-next-line reentrancy-no-eth
    function _burnWalk(address token, uint256 remaining, bytes memory burnInfo) internal returns (uint256 idx) {
        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(token));
        IERC1155 vaultReceipt = IERC1155(address(vault.receipt()));
        idx = _main().nextBurnReceiptId[token];
        uint256 cap = vault.highwaterId();
        while (remaining > 0) {
            if (idx > cap) revert InsufficientReceipts(token, remaining);
            // One rebased balanceOf per inspected id.
            // slither-disable-next-line calls-loop
            uint256 bal = vaultReceipt.balanceOf(address(this), idx);
            if (bal == 0) {
                unchecked {
                    idx++;
                }
                continue;
            }
            uint256 take = remaining < bal ? remaining : bal;
            // Share ratio is 1:1; anything else halts the burn.
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

    /// @inheritdoc IST0xOrchestratorV2
    /// @dev O(gap) hazard, both directions: set too LOW and the next `burn`
    /// pays one external rebased `balanceOf` per id to cross the gap in a
    /// single tx; set too high and held receipts behind the pointer are
    /// stranded, so burns revert `InsufficientReceipts` once the receipts
    /// ahead of it are exhausted. Set at (or just below) the first id with
    /// non-zero balance. The receiver hook lowers the pointer when a receipt
    /// arrives below it.
    function setBurnIndex(address token, uint256 newIndex) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        MainStorage storage $ = _main();
        uint256 old = $.nextBurnReceiptId[token];
        $.nextBurnReceiptId[token] = newIndex;
        emit BurnIndexSet(token, old, newIndex);
    }

    // ------------------------------------------------------------------ //
    //                            Mint caps                               //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV2
    /// @dev The bucket is settled at the outgoing rate up to now, then the new
    /// policy is written (`LibLeakyBucket.setPolicy`, which refuses a negative
    /// capacity or leak rate), so each rate is charged only for the time it was
    /// in force. An unset limit holds a zero rate, so a first limit starts from
    /// the level the bucket already holds. A lowered capacity binds
    /// immediately against the settled level.
    function setMintLimit(MintCapKind kind, address account, Float capacity, Float leakRate)
        external
        onlyRole(MINT_ADMIN_ROLE)
    {
        MintCapV1 storage cap = _main().mintCaps[kind][account];
        cap.bucket = LibLeakyBucket.setPolicy(cap.bucket, _now(), capacity, leakRate);
        cap.set = true;
        emit MintLimitSet(kind, account, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV2
    /// @dev Stored as given. Nothing is validated here: the bytecode is judged
    /// by the interpreter at the first mint. The buckets are left where the
    /// earlier mints put them; a new weighting changes what the next mint is
    /// charged, not what has been charged.
    function setMintWeighting(EvaluableV4 calldata evaluable) external onlyRole(MINT_ADMIN_ROLE) {
        _main().mintWeighting = evaluable;
        emit MintWeightingSet(msg.sender, evaluable);
    }

    // ------------------------------------------------------------------ //
    //                           Emergency sweeps                         //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV2
    function withdrawReceipt(address token, uint256 id, uint256 amount, address to)
        external
        onlyRole(EMERGENCY_ROLE)
        nonReentrant
    {
        IERC1155(address(OffchainAssetReceiptVault(payable(token)).receipt()))
            .safeTransferFrom(address(this), to, id, amount, "");
        emit ReceiptsWithdrawn(token, to, id, amount);
    }

    /// @inheritdoc IST0xOrchestratorV2
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

    /// @inheritdoc IST0xOrchestratorV2
    /// @dev Sweeps tStocks stranded on the orchestrator (sent directly to it,
    /// or rebase-truncation dust after fractional splits).
    function withdrawShares(address token, uint256 amount, address to) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        IERC20(token).safeTransfer(to, amount);
        emit SharesWithdrawn(token, to, amount);
    }

    // ------------------------------------------------------------------ //
    //                              Views                                 //
    // ------------------------------------------------------------------ //

    /// @inheritdoc IST0xOrchestratorV2
    function nextBurnReceiptId(address token) external view returns (uint256) {
        return _main().nextBurnReceiptId[token];
    }

    /// @inheritdoc IST0xOrchestratorV2
    function nonceUsed(address to, bytes32 nonce) external view returns (bool) {
        return _main().usedNonce[to][nonce];
    }

    /// @inheritdoc IST0xOrchestratorV2
    function mintAuthDigest(address token, address to, uint256 amount, bytes32 nonce) external view returns (Digest) {
        return _mintAuthDigest(token, to, amount, nonce);
    }

    /// @inheritdoc IST0xOrchestratorV2
    function mintLimit(MintCapKind kind, address account) external view returns (MintLimitV1 memory) {
        MintCapV1 storage cap = _main().mintCaps[kind][account];
        return MintLimitV1({capacity: cap.bucket.capacity, leakRate: cap.bucket.leakRate, set: cap.set});
    }

    /// @inheritdoc IST0xOrchestratorV2
    function mintWeighting() external view returns (EvaluableV4 memory) {
        return _main().mintWeighting;
    }

    /// @inheritdoc IST0xOrchestratorV2
    /// @dev Zero for an unset limit, matching what a mint would do: an unset
    /// limit admits nothing.
    function mintHeadroom(address minter, address recipient) external view returns (Float) {
        MainStorage storage $ = _main();
        MintCapV1 storage minterCap = $.mintCaps[MintCapKind.Minter][minter];
        MintCapV1 storage recipientCap = $.mintCaps[MintCapKind.Recipient][recipient];

        if (!minterCap.set) return LibDecimalFloat.FLOAT_ZERO;
        if (!recipientCap.set) return LibDecimalFloat.FLOAT_ZERO;

        Float timestamp = _now();
        Float minterHeadroom = LibLeakyBucket.headroomAt(minterCap.bucket, timestamp);
        Float recipientHeadroom = LibLeakyBucket.headroomAt(recipientCap.bucket, timestamp);

        return LibDecimalFloat.min(minterHeadroom, recipientHeadroom);
    }

    /// @inheritdoc IST0xOrchestratorV2
    function mintLevel(MintCapKind kind, address account) external view returns (Float) {
        return LibLeakyBucket.levelAt(_main().mintCaps[kind][account].bucket, _now());
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
    /// is recoverable via `sweepERC1155`). When the sender is a production
    /// receipt, a receipt arriving at an id below `token`'s pointer lowers the
    /// pointer to that id.
    ///
    /// Only a non-zero transfer lowers the pointer. A zero-value transfer
    /// delivers no burnable balance, and lowering onto an empty id would let
    /// any account, at no cost, inflate the next burn's walk to
    /// `O(highwaterId)`.
    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata) external returns (bytes4) {
        if (value > 0) _maybeLowerBurnIndex(msg.sender, id);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata values, bytes calldata)
        external
        returns (bytes4)
    {
        // A hand-crafted direct call may pass unequal arrays; the accept-all hooks never revert.
        for (uint256 i = 0; i < ids.length; i++) {
            if (i < values.length && values[i] > 0) _maybeLowerBurnIndex(msg.sender, ids[i]);
        }
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @dev If `erc1155` is a production receipt (its claimed vault
    /// round-trips: `vault.receipt() == erc1155`) and `id` is below that
    /// vault's burn pointer, lower the pointer to `id`. The probes are raw
    /// staticcalls, so a foreign or malicious ERC-1155 cannot revert the
    /// transfer; spoofing a pointer move requires controlling
    /// `vault.receipt()`.
    function _maybeLowerBurnIndex(address erc1155, uint256 id) internal {
        // Raw staticcalls: typed try/catch cannot catch a returndata-decode failure.
        // slither-disable-next-line low-level-calls,calls-loop
        (bool ok, bytes memory ret) = erc1155.staticcall(abi.encodeWithSelector(IReceiptV3.manager.selector));
        if (!ok || ret.length != 32) return;
        // Truncating to 160 bits is the decode; dirty high bits fail the comparison below.
        // forge-lint: disable-next-line(unsafe-typecast)
        address vault = address(uint160(uint256(bytes32(ret))));
        // slither-disable-next-line low-level-calls,calls-loop
        (ok, ret) = vault.staticcall(abi.encodeWithSelector(ReceiptVault.receipt.selector));
        if (!ok || ret.length != 32) return;
        // Truncating to 160 bits is the decode; dirty high bits fail the comparison below.
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
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IST0xOrchestratorV2).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @dev `ReceiptVault.mint` is payable and refunds any ETH the vault
    /// holds to `msg.sender` (this orchestrator) via `Address.sendValue`.
    /// There is no ETH sweep.
    // slither-disable-next-line locked-ether
    receive() external payable {}
}
