// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {SignatureChecker} from "@openzeppelin-contracts-5.6.1/utils/cryptography/SignatureChecker.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.2.1/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {IReceiptV3} from "rain-vats-0.2.1/src/interface/IReceiptV3.sol";
import {ReceiptVault} from "rain-vats-0.2.1/src/abstract/ReceiptVault.sol";

import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {LibLeakyBucket, LeakyBucket} from "rain-lib-leakybucket-0.4.1/src/lib/LibLeakyBucket.sol";
import {LibIntOrAString, IntOrAString} from "rain-intorastring-0.1.0/src/lib/LibIntOrAString.sol";
import {
    IInterpreterCallerV4,
    EvaluableV4,
    SignedContextV1
} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";
import {
    EvalV4,
    SourceIndexV2,
    StackItem,
    StateNamespace,
    DEFAULT_STATE_NAMESPACE
} from "rainlang-interface-0.2.9/src/interface/IInterpreterV4.sol";
import {LibNamespace} from "rainlang-interface-0.2.9/src/lib/ns/LibNamespace.sol";

import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {IMintRecipient} from "../interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../interface/IST0xVaultBeaconSet.sol";
import {IST0xOrchestratorV1, MintAuthV1, MintLimitV1, MintBucketV1, Digest} from "../interface/IST0xOrchestratorV1.sol";
import {LibSt0xAttestContext} from "../lib/LibSt0xAttestContext.sol";

/// @title ST0xOrchestrator
/// @notice Singleton mint/burn proxy for the ST0x receipt-vault set. One
/// instance (behind a beacon proxy) serves every token; all per-token state
/// is keyed by the token's `OffchainAssetReceiptVault` address. It holds the
/// vault-side `DEPOSIT` + `WITHDRAW` roles and owns every receipt; callers
/// never touch one.
///
/// **Roles.** Every role that does something has its own admin role, and
/// `DEFAULT_ADMIN_ROLE` administers only those admin roles — it performs no
/// operations at all.
///  - `MINT_ADMIN_ROLE` — grant `MINT_ROLE`, set the mint caps and the mint
///    weighting.
///  - `MINT_ROLE` — call `mint`.
///  - `BURN_ADMIN_ROLE` — grant `BURN_ROLE`. The burn side has no policy to
///    set, so that is the whole of it.
///  - `BURN_ROLE` — call `burn`.
///  - `EMERGENCY_ADMIN_ROLE` — grant `EMERGENCY_ROLE`, and nothing else.
///    Saying who may hold the recovery key is not holding it.
///  - `EMERGENCY_ROLE` — recovery ops (`setBurnIndex`, `withdrawReceipt`,
///    `withdrawShares`, `sweepERC1155`). Deliberately separate from
///    mint/burn, so the key that can reposition pointers or sweep assets can
///    never also mint.
///
/// An admin role is held separately from the role it administers: granting
/// `MINT_ADMIN_ROLE` does not grant `MINT_ROLE`, and `initialize` grants only
/// the admin roles.
///
/// `initialize` wires that split. A proxy that initialised against an
/// implementation without the three admin roles carries neither the grants
/// nor the delegations, and `initializeV2` is the one call that installs
/// them.
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
/// **Vault-logic version lock.** `initialize`, `mint` and `burn` revert
/// unless the production vault + receipt beacons point at the implementations
/// in `LibProdDeployCurrent`. If the vault is upgraded, the orchestrator halts
/// until its own implementation is upgraded.
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
/// attestations the minter passed, every signature verified) and evaluates
/// the expression over it. The last output is the charge on both buckets.
/// What the attestations must say is the expression's to check and revert
/// on; the orchestrator verifies only that each attestation was signed by the
/// signer it names. State the expression writes is persisted to its store
/// under the orchestrator's namespace.
///
/// The bucket library refuses a negative capacity, a negative leak rate, a
/// zero charge and a negative charge, at every read and every fill; the
/// setters store what they are given. A weighting that evaluates to zero or
/// below is a refused mint.
contract ST0xOrchestrator is
    IST0xOrchestratorV1,
    IInterpreterCallerV4,
    Initializable,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardTransient,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;
    using LibDecimalFloat for Float;

    bytes32 public constant MINT_ROLE = keccak256("MINT");
    /// @notice Administers `MINT_ROLE` and sets the mint caps and the mint
    /// weighting.
    bytes32 public constant MINT_ADMIN_ROLE = keccak256("MINT_ADMIN");
    bytes32 public constant BURN_ROLE = keccak256("BURN");
    /// @notice Administers `BURN_ROLE`. The burn side carries no policy to
    /// set, so granting and revoking `BURN_ROLE` is all this role does — the
    /// burn-pointer repair is `EMERGENCY_ROLE`'s, deliberately apart from
    /// both.
    bytes32 public constant BURN_ADMIN_ROLE = keccak256("BURN_ADMIN");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY");
    /// @notice Administers `EMERGENCY_ROLE`. Holding this is not holding
    /// `EMERGENCY_ROLE`: it says who may be handed the recovery key, never
    /// that its holder may turn it.
    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN");

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
        /// Each minter's cap: its policy across every token and recipient,
        /// and the bucket under it.
        mapping(address minter => MintCapV1) minterMintCaps;
        /// Each recipient's cap: its policy across every token and minter,
        /// and the bucket under it.
        mapping(address recipient => MintCapV1) recipientMintCaps;
        /// The mint weighting: the one expression that converts every mint
        /// into the charge on both buckets. A zero interpreter is unset.
        EvaluableV4 mintWeighting;
    }

    /// @dev One cap: a policy and the bucket metered under it. A bucket is
    /// two words, `(level, timestamp)`, and two zero words are an unused
    /// bucket. Live storage holds the members in this order; they are never
    /// reordered.
    /// @param limit The policy, as set.
    /// @param bucket The bucket under `limit`.
    struct MintCapV1 {
        MintLimitV1 limit;
        MintBucketV1 bucket;
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

    // The implementation disables initializers; the proxy initialises via
    // `initialize`.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the singleton. Grants `DEFAULT_ADMIN_ROLE`,
    /// `MINT_ADMIN_ROLE` and `BURN_ADMIN_ROLE` to `owner`, and delegates
    /// `MINT_ROLE` to `MINT_ADMIN_ROLE` and `BURN_ROLE` to
    /// `BURN_ADMIN_ROLE`. `MINT_ROLE`, `BURN_ROLE` and `EMERGENCY_ROLE` are
    /// granted separately. Reverts unless the vault-logic version lock
    /// passes.
    /// @param owner Address granted `DEFAULT_ADMIN_ROLE`, `MINT_ADMIN_ROLE`
    /// and `BURN_ADMIN_ROLE`.
    function initialize(address owner) external initializer {
        if (owner == address(0)) revert ZeroOwner();
        _checkVaultLogic();
        __AccessControl_init();
        __EIP712_init("ST0xOrchestrator", "1");
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(MINT_ADMIN_ROLE, owner);
        _setRoleAdmin(MINT_ROLE, MINT_ADMIN_ROLE);
        _grantRole(BURN_ADMIN_ROLE, owner);
        _setRoleAdmin(BURN_ROLE, BURN_ADMIN_ROLE);
        _grantRole(EMERGENCY_ADMIN_ROLE, owner);
        _setRoleAdmin(EMERGENCY_ROLE, EMERGENCY_ADMIN_ROLE);
    }

    /// @notice Reconcile a proxy whose `initialize` ran against an
    /// implementation that had none of the admin roles. Such a proxy holds
    /// `MINT_ADMIN_ROLE`, `BURN_ADMIN_ROLE` and `EMERGENCY_ADMIN_ROLE` for
    /// nobody and leaves `DEFAULT_ADMIN_ROLE` as the admin of all three
    /// operating roles, so the mint caps and the mint weighting are
    /// unsettable and the role split this contract documents holds on no
    /// side. Grants the three admin roles to the caller and delegates each
    /// operating role to its own — the six writes `initialize` performs and
    /// nothing else, so a proxy reconciled here is indistinguishable from
    /// one initialised at this version.
    ///
    /// @dev A call refused on authorisation reverts in full, so it cannot
    /// consume the proxy's one shot — the version write rolls back with
    /// everything else, whichever modifier checks first.
    ///
    /// `reinitializer(2)` admits one call per proxy. A proxy initialised
    /// by this implementation is already in the reconciled state yet still
    /// sits at version 1, so the call is open on it too; it re-grants the
    /// caller roles the caller must already administer and rewrites the same
    /// admins, so it changes nothing there. Marking `initialize` itself
    /// `reinitializer(2)` would close that at the cost of leaving an ungated
    /// `initialize` callable on every version-1 proxy, which would hand
    /// `DEFAULT_ADMIN_ROLE` to any caller.
    ///
    /// The caller takes the roles rather than an address argument: it must
    /// hold `DEFAULT_ADMIN_ROLE` already, which is the same authority
    /// `initialize` grants all three to.
    function initializeV2() external onlyRole(DEFAULT_ADMIN_ROLE) reinitializer(2) {
        _grantRole(MINT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(MINT_ROLE, MINT_ADMIN_ROLE);
        _grantRole(BURN_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(BURN_ROLE, BURN_ADMIN_ROLE);
        _grantRole(EMERGENCY_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(EMERGENCY_ROLE, EMERGENCY_ADMIN_ROLE);
    }

    // ------------------------------------------------------------------ //
    //                       Vault-logic version lock                     //
    // ------------------------------------------------------------------ //

    /// @dev Revert unless the shared production vault + receipt beacons point
    /// at the implementations pinned in `LibProdDeployCurrent`. Every
    /// production token is a `BeaconProxy` of these two beacons. The check is
    /// of the shared beacons, not the `token` argument: a `token` that is not
    /// a proxy of the shared set is not covered by the lock, and has not
    /// granted the orchestrator `DEPOSIT`/`WITHDRAW`, so mint/burn on it
    /// revert at the vault authoriser.
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
    // The nonce write in `_consumeMintAuth` follows the weighting's store
    // write and the recipient callback; `nonReentrant` holds the
    // ReentrancyGuardTransient lock for the whole entrypoint.
    // slither-disable-next-line reentrancy-no-eth
    function mint(
        address token,
        address to,
        uint256 amount,
        MintAuthV1 calldata auth,
        bytes calldata receiptInformation,
        SignedContextV1[] calldata attestations
    ) external onlyRole(MINT_ROLE) onlyExpectedVaultLogic nonReentrant {
        if (amount == 0) revert ZeroAmount();
        // The sender and the recipient can never be the same.
        if (to == msg.sender) revert SenderIsRecipient(msg.sender);
        _consumeMintCaps(token, to, amount, attestations);
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
    function _consumeMintCaps(address token, address to, uint256 amount, SignedContextV1[] calldata attestations)
        internal
    {
        MainStorage storage $ = _main();
        MintCapV1 storage minterCap = $.minterMintCaps[msg.sender];
        MintCapV1 storage recipientCap = $.recipientMintCaps[to];
        MintLimitV1 memory minterLimit = minterCap.limit;
        if (!minterLimit.set) revert MinterGlobalMintLimitUnset(msg.sender);
        MintLimitV1 memory recipientLimit = recipientCap.limit;
        if (!recipientLimit.set) revert RecipientMintLimitUnset(to);

        // The charge is what the mint weighting says this mint is worth; the
        // amount as passed never reaches the buckets.
        Float charge = _weighMint($, token, amount, attestations);
        Float timestamp = _now();
        _fillMinterMintCap(minterCap, minterLimit, timestamp, charge);
        _fillRecipientMintCap(recipientCap, recipientLimit, to, timestamp, charge);
    }

    /// @dev Evaluate the mint weighting over this mint and its attestations
    /// and return the charge. Reverts `MintWeightingUnset` if no expression
    /// has been set, `UnsupportedMintWeightingOutputs` if the expression left
    /// nothing on its stack, and with whatever the expression itself reverts
    /// with.
    ///
    /// The context is the grid of `LibSt0xAttestContext`: the token's symbol
    /// as an `IntOrAString`, and the amount as a `Float` in whole tokens per
    /// the token's `decimals()`. Building the grid verifies every
    /// attestation's signature and reverts `InvalidSignature(i)` on the first
    /// that fails.
    ///
    /// The evaluation is a static call; the writes it returns are then
    /// applied to the expression's store under the orchestrator's namespace.
    /// Split out of `_consumeMintCaps` to keep that frame within stack limits.
    function _weighMint(MainStorage storage $, address token, uint256 amount, SignedContextV1[] calldata attestations)
        internal
        returns (Float)
    {
        EvaluableV4 memory evaluable = $.mintWeighting;
        if (address(evaluable.interpreter) == address(0)) revert MintWeightingUnset();

        bytes32[][] memory context = LibSt0xAttestContext.build(
            bytes32(IntOrAString.unwrap(LibIntOrAString.fromStringV3(IERC20Metadata(token).symbol()))),
            Float.unwrap(LibDecimalFloat.fromFixedDecimalLosslessPacked(amount, IERC20Metadata(token).decimals())),
            attestations
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
        // The interpreter returns the stack top first, so the last output the
        // expression wrote is item zero.
        return Float.wrap(StackItem.unwrap(stack[0]));
    }

    /// @dev The minter's bucket, across every token and recipient. Split out
    /// of `_consumeMintCaps` to keep that frame within stack limits.
    // The bucket write follows the weighting's external calls; every caller
    // holds the reentrancy lock for the whole entrypoint.
    // slither-disable-next-line reentrancy-no-eth
    function _fillMinterMintCap(MintCapV1 storage cap, MintLimitV1 memory limit, Float timestamp, Float charge)
        internal
    {
        LeakyBucket memory bucket = _bucket(cap.bucket, limit);
        Float headroom = LibLeakyBucket.headroomAt(bucket, timestamp);
        if (charge.gt(headroom)) revert MinterGlobalMintCapExceeded(msg.sender, limit.capacity, headroom, charge);

        (Float level, Float checkpoint) = LibLeakyBucket.fill(bucket, timestamp, charge);
        cap.bucket = MintBucketV1({level: level, timestamp: checkpoint});
    }

    /// @dev The recipient's bucket, across every token and minter.
    // As `_fillMinterMintCap`.
    // slither-disable-next-line reentrancy-no-eth
    function _fillRecipientMintCap(
        MintCapV1 storage cap,
        MintLimitV1 memory limit,
        address to,
        Float timestamp,
        Float charge
    ) internal {
        LeakyBucket memory bucket = _bucket(cap.bucket, limit);
        Float headroom = LibLeakyBucket.headroomAt(bucket, timestamp);
        if (charge.gt(headroom)) revert RecipientMintCapExceeded(to, limit.capacity, headroom, charge);

        (Float level, Float checkpoint) = LibLeakyBucket.fill(bucket, timestamp, charge);
        cap.bucket = MintBucketV1({level: level, timestamp: checkpoint});
    }

    /// @dev A stored bucket under a limit, as the library takes it.
    function _bucket(MintBucketV1 memory stored, MintLimitV1 memory limit) internal pure returns (LeakyBucket memory) {
        return LeakyBucket({
            level: stored.level, timestamp: stored.timestamp, capacity: limit.capacity, leakRate: limit.leakRate
        });
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
    /// amount still unburned. Persists and returns the final pointer. Split
    /// out of `burn`, and `burnInfo` taken as `memory`, to keep both frames
    /// within stack limits.
    // Pointer write after external calls: every caller holds the
    // ReentrancyGuardTransient lock for the whole entrypoint.
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

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev O(gap) hazard, both directions: set too low and the next `burn`
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

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev Neither magnitude nor sign is checked here; the bucket library
    /// refuses a negative capacity or leak rate at every read and fill, so a
    /// policy written negative fails closed.
    ///
    /// Only the policy is written; the bucket's level is left where the
    /// earlier mints put it, so a lowered capacity binds immediately.
    function setMinterGlobalMintLimit(address minter, Float capacity, Float leakRate)
        external
        onlyRole(MINT_ADMIN_ROLE)
    {
        _main().minterMintCaps[minter].limit = MintLimitV1({capacity: capacity, leakRate: leakRate, set: true});
        emit MinterGlobalMintLimitSet(minter, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev Same terms as `setMinterGlobalMintLimit`: the policy is written,
    /// the bucket's level is left where the earlier mints put it.
    function setRecipientMintLimit(address recipient, Float capacity, Float leakRate)
        external
        onlyRole(MINT_ADMIN_ROLE)
    {
        _main().recipientMintCaps[recipient].limit = MintLimitV1({capacity: capacity, leakRate: leakRate, set: true});
        emit RecipientMintLimitSet(recipient, capacity, leakRate);
    }

    /// @inheritdoc IST0xOrchestratorV1
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
    /// @dev The receiver hooks accept all senders, so this is the recovery
    /// path for a foreign ERC-1155 that lands here.
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
        return _main().minterMintCaps[minter].limit;
    }

    /// @inheritdoc IST0xOrchestratorV1
    function recipientMintLimit(address recipient) external view returns (MintLimitV1 memory) {
        return _main().recipientMintCaps[recipient].limit;
    }

    /// @inheritdoc IST0xOrchestratorV1
    function mintWeighting() external view returns (EvaluableV4 memory) {
        return _main().mintWeighting;
    }

    /// @inheritdoc IST0xOrchestratorV1
    /// @dev Zero for an unset limit, matching what a mint would do: an unset
    /// limit admits nothing.
    function mintHeadroom(address minter, address recipient) external view returns (Float) {
        MainStorage storage $ = _main();
        MintCapV1 storage minterCap = $.minterMintCaps[minter];
        MintCapV1 storage recipientCap = $.recipientMintCaps[recipient];

        MintLimitV1 memory minterLimit = minterCap.limit;
        if (!minterLimit.set) return LibDecimalFloat.FLOAT_ZERO;
        MintLimitV1 memory recipientLimit = recipientCap.limit;
        if (!recipientLimit.set) return LibDecimalFloat.FLOAT_ZERO;

        Float timestamp = _now();
        Float minterHeadroom = LibLeakyBucket.headroomAt(_bucket(minterCap.bucket, minterLimit), timestamp);
        Float recipientHeadroom = LibLeakyBucket.headroomAt(_bucket(recipientCap.bucket, recipientLimit), timestamp);

        return LibDecimalFloat.min(minterHeadroom, recipientHeadroom);
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
        // An ERC-1155 batch passes equal-length arrays; the `i < values.length`
        // bound covers a hand-crafted direct call, which the accept-all hooks
        // never revert on.
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
        // Raw staticcalls: typed try/catch cannot catch returndata-decode
        // failures, so a malformed return could revert the hook and block
        // transfers.
        // slither-disable-next-line low-level-calls,calls-loop
        (bool ok, bytes memory ret) = erc1155.staticcall(abi.encodeWithSelector(IReceiptV3.manager.selector));
        if (!ok || ret.length != 32) return;
        // Truncating the 32-byte return to 160 bits is the decode; dirty high
        // bits fail the comparison below.
        // forge-lint: disable-next-line(unsafe-typecast)
        address vault = address(uint160(uint256(bytes32(ret))));
        // slither-disable-next-line low-level-calls,calls-loop
        (ok, ret) = vault.staticcall(abi.encodeWithSelector(ReceiptVault.receipt.selector));
        if (!ok || ret.length != 32) return;
        // Truncating the 32-byte return to 160 bits is the decode; dirty high
        // bits fail the comparison below.
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
    /// holds to `msg.sender` (this orchestrator) via `Address.sendValue`.
    /// There is no ETH sweep.
    // slither-disable-next-line locked-ether
    receive() external payable {}
}
