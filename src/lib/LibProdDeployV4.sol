// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;
import {
    CREATION_CODE as STOX_RECEIPT_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_RECEIPT_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxReceipt.pointers.sol";
import {
    CREATION_CODE as STOX_RECEIPT_VAULT_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_RECEIPT_VAULT_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxReceiptVault.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxWrappedTokenVault.pointers.sol";
import {
    CREATION_CODE as STOX_UNIFIED_DEPLOYER_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_UNIFIED_DEPLOYER_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxUnifiedDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    CREATION_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {
    CREATION_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.pointers.sol";
import {
    CREATION_CODE as STOX_CORPORATE_ACTIONS_FACET_CREATION_0_1_1_GEN,
    RUNTIME_CODE as STOX_CORPORATE_ACTIONS_FACET_RUNTIME_0_1_1_GEN
} from "../generated/0_1_1/StoxCorporateActionsFacet.pointers.sol";
import {
    CREATION_CODE as STOX_RECEIPT_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_RECEIPT_RUNTIME_0_1_2_GEN
} from "../generated/StoxReceipt.pointers.sol";
import {
    CREATION_CODE as STOX_RECEIPT_VAULT_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_RECEIPT_VAULT_RUNTIME_0_1_2_GEN
} from "../generated/StoxReceiptVault.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_RUNTIME_0_1_2_GEN
} from "../generated/StoxWrappedTokenVault.pointers.sol";
import {
    CREATION_CODE as STOX_UNIFIED_DEPLOYER_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_UNIFIED_DEPLOYER_RUNTIME_0_1_2_GEN
} from "../generated/StoxUnifiedDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_0_1_2_GEN
} from "../generated/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    CREATION_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_2_GEN
} from "../generated/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_2_GEN
} from "../generated/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_0_1_2_GEN
} from "../generated/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {
    CREATION_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_0_1_2_GEN
} from "../generated/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.pointers.sol";
import {
    CREATION_CODE as STOX_CORPORATE_ACTIONS_FACET_CREATION_0_1_2_GEN,
    RUNTIME_CODE as STOX_CORPORATE_ACTIONS_FACET_RUNTIME_0_1_2_GEN
} from "../generated/StoxCorporateActionsFacet.pointers.sol";
import {
    CREATION_CODE as ST0X_ORCHESTRATOR_CREATION_0_1_2_GEN,
    RUNTIME_CODE as ST0X_ORCHESTRATOR_RUNTIME_0_1_2_GEN
} from "../generated/ST0xOrchestrator.pointers.sol";
import {
    CREATION_CODE as ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_0_1_2_GEN,
    RUNTIME_CODE as ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_RUNTIME_0_1_2_GEN
} from "../generated/ST0xOrchestratorBeaconSetDeployer.pointers.sol";

/// @title LibProdDeployV4
/// @notice V4 production deployment pins for the ST0x contract set on Base,
/// rebuilt against the audited rain.vats `sol-v0.1.6` tag (Renascence Labs
/// audit dated 2026-06; H01 "ERC1155 acceptance callback enables persistent
/// operator approval via `_msgSender` spoofing" fixed at upstream commit
/// `5275093` and reflected as the 0.1.6 Soldeer pin in `foundry.toml`).
/// Every deterministic Zoltu address derives from the compiled bytecode, so
/// every ST0x contract whose source-or-dependency tree changed under the
/// rain.vats bump gets a new V4 address here.
///
/// **The clone (`STOX_PROD_AUTHORISER_V4_CLONE`) is still `address(0)`** —
/// it gets hydrated by the V4 authoriser deploy script (sibling PR), which
/// is the only entry that isn't deterministic at lib-author time. Every
/// other address + codehash pair is the Zoltu-deterministic value generated
/// by `script/BuildPointers.sol` against rain.vats 0.1.6 and mirrors the
/// `DEPLOYED_ADDRESS` constants in `src/generated/*.pointers.sol`.
///
/// Naming convention: each deployed-contract constant is suffixed with the
/// **st0x-deploy release tag** it belongs to (`_0_1_1`, `_0_1_2`), NOT the
/// rain.vats dependency version. A deployed address is a function of the
/// contract's own source AND its dependency tree, so an st0x-only source
/// change moves addresses with no rain.vats bump — keying the suffix on the
/// dependency alone was both incomplete and misleading. `0_1_1` is the
/// current published release; `0_1_2` is the next release: the 0.1.1 set at
/// identical addresses plus the ST0x orchestrator + its deployer. A future
/// release adds a new suffixed set rather than overwriting a frozen one. The
/// lib name itself is generic (`LibProdDeployV4`).
///
/// The frozen pre-V4 deployments are pinned in `LibProdDeployV1` and
/// `LibProdDeployV2` as audit trails; active source and scripts reference this
/// (latest) lib.
library LibProdDeployV4 {
    /// @notice The current st0x-deploy release tag these constants pin.
    /// Encoded in every deployed-contract constant name (e.g.
    /// `STOX_RECEIPT_0_1_2`) so a future release produces a new constant set
    /// alongside this one rather than silently overwriting it.
    /// @dev String constant, present only as a written reminder — Solidity has
    /// no preprocessor so future renames must be done by hand in the source.
    string constant DEPLOY_TAG = "0_1_2";

    /// @notice The beacon initial owner. Resolves to rainlang.eth. Unchanged
    /// across V1 / V2 / V3 / V4; this is the EOA that receives ownership at
    /// deploy time and is migrated to the ST0x token-owner Safe by
    /// `LibProdMigrateBeaconOwnership`.
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    // =========================================================================
    // st0x-deploy release 0.1.1 — the current published release (frozen).
    //
    // Each `_0_1_1` pair is the deterministic Zoltu address + runtime codehash
    // for an ST0x contract, built against the audited `rain-vats = "0.1.6"`
    // dependency (see `foundry.toml`). The addresses match the
    // `DEPLOYED_ADDRESS` constants in `src/generated/*.pointers.sol` — the
    // authoritative source generated by `script/BuildPointers.sol`. The
    // codehashes are `keccak256(RUNTIME_CODE)` from the same pointer files; a
    // future `BuildPointers` run regenerates them in lockstep with any change
    // to the source or the rain.vats dependency.
    // =========================================================================

    address constant STOX_RECEIPT_0_1_1 = address(0x2dF5cFE6d688EF9fF1B7c59A499D254b1527b286);
    bytes32 constant STOX_RECEIPT_CODEHASH_0_1_1 = 0x06fffbad12ea80897d55aab5d4f1cd3f34f674237db44a148cc133334a0cca54;

    address constant STOX_RECEIPT_VAULT_0_1_1 = address(0x2BCcEd626566Ef1e65F922DD03748C5C7aa2d748);
    bytes32 constant STOX_RECEIPT_VAULT_CODEHASH_0_1_1 =
        0x11da975b8024dd98441bfdf42a68462fa5db9bd4e3af348f05928ef359924671;

    address constant STOX_WRAPPED_TOKEN_VAULT_0_1_1 = address(0x0D99e0174DbF885ceD6AE8dEb939b0F890450099);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_CODEHASH_0_1_1 =
        0x6de4c556c1811293da4ad2e509ee476f3eb635f019845087e1d2777a1b272034;

    address constant STOX_UNIFIED_DEPLOYER_0_1_1 = address(0x81D0ecD58346bf2d484E7774f55EABc1AA3F4bcc);
    bytes32 constant STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_1 =
        0x91035080d8e610cc0657d7f44efa8fbf57ce5800e6a35694d107c05987d24e3f;

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1 = address(0x9FD790f65CA3aF2772358c653F097f0a4c7EE7d2);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_0_1_1 =
        0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630;

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1 =
        address(0xd64246e6b25F745f005E6233e050C9B879E660Dc);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1 =
        0x621c1edbd850939acba8bcd999812a83999b5680d4ca6804e1995b95f138b9e5;

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1 =
        address(0xbe5f05C4576e6D3e7bCCb4E64f08fc4F46Adf0cA);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1 =
        0xa2c4bd29f36bc6636938f3ad66e6de5d126ce41ed3134bed166cde259d5775ad;

    /// @dev The corporate-action-aware authoriser impl. The clone deployed
    /// for the issuer (see `STOX_PROD_AUTHORISER_V4_CLONE` below) points
    /// at this impl via EIP-1167.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1 =
        address(0x2EA0d35d0B1F57C42e6130f298930228bCbFDe9b);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1 =
        0xf8a1d9b2fa068bae3c1a607434db48364a5cdab3020bd7e315ed2662a3b35b5f;

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_1 =
        address(0xeaD68E489Cb19453b294dc46a3A5710b0d46d17F);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_0_1_1 =
        0x4d94318cde48f1bc20f97e00aefad84bfb7c9db15c81b882862e127b05e06e15;

    /// @dev The corporate-actions facet. The receipt vault's `fallback()`
    /// hardcodes this address and delegatecalls every non-matching selector
    /// here, so a facet bytecode change forces a vault impl redeploy too. With
    /// the new rain.vats tag the receipt vault impl is rebuilt, so this facet
    /// is rebuilt in lock-step.
    address constant STOX_CORPORATE_ACTIONS_FACET_0_1_1 = address(0x51f78B77EdffDB62b8AeB753066C318a46D05D74);
    bytes32 constant STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_1 =
        0x2a67c52129dff74d956bb7dcde1aac598c28dd29685237aca56dccb1d49bd6f8;

    // =========================================================================
    // st0x-deploy release 0.1.2 — the next release (= 0.1.1 + orchestrator).
    //
    // The ten contracts above are unchanged, so each `_0_1_2` pin below holds
    // the SAME address + codehash as its `_0_1_1` twin; the release adds the
    // ST0x orchestrator and its Zoltu deployer. Deploy wiring targets this
    // (current) release. As with 0.1.1 these are the deterministic Zoltu values
    // from `src/generated/*.pointers.sol`, generated by
    // `script/BuildPointers.sol`.
    // =========================================================================

    address constant STOX_RECEIPT_0_1_2 = address(0x2dF5cFE6d688EF9fF1B7c59A499D254b1527b286);
    bytes32 constant STOX_RECEIPT_CODEHASH_0_1_2 = 0x06fffbad12ea80897d55aab5d4f1cd3f34f674237db44a148cc133334a0cca54;

    address constant STOX_RECEIPT_VAULT_0_1_2 = address(0x2BCcEd626566Ef1e65F922DD03748C5C7aa2d748);
    bytes32 constant STOX_RECEIPT_VAULT_CODEHASH_0_1_2 =
        0x11da975b8024dd98441bfdf42a68462fa5db9bd4e3af348f05928ef359924671;

    address constant STOX_WRAPPED_TOKEN_VAULT_0_1_2 = address(0x0D99e0174DbF885ceD6AE8dEb939b0F890450099);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_CODEHASH_0_1_2 =
        0x6de4c556c1811293da4ad2e509ee476f3eb635f019845087e1d2777a1b272034;

    address constant STOX_UNIFIED_DEPLOYER_0_1_2 = address(0x81D0ecD58346bf2d484E7774f55EABc1AA3F4bcc);
    bytes32 constant STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_2 =
        0x91035080d8e610cc0657d7f44efa8fbf57ce5800e6a35694d107c05987d24e3f;

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_2 = address(0x9FD790f65CA3aF2772358c653F097f0a4c7EE7d2);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH_0_1_2 =
        0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630;

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_2 =
        address(0xd64246e6b25F745f005E6233e050C9B879E660Dc);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_2 =
        0x621c1edbd850939acba8bcd999812a83999b5680d4ca6804e1995b95f138b9e5;

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_2 =
        address(0xbe5f05C4576e6D3e7bCCb4E64f08fc4F46Adf0cA);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_2 =
        0xa2c4bd29f36bc6636938f3ad66e6de5d126ce41ed3134bed166cde259d5775ad;

    /// @dev The corporate-action-aware authoriser impl. The clone deployed
    /// for the issuer (see `STOX_PROD_AUTHORISER_V4_CLONE` below) points
    /// at this impl via EIP-1167.
    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_2 =
        address(0x2EA0d35d0B1F57C42e6130f298930228bCbFDe9b);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_2 =
        0xf8a1d9b2fa068bae3c1a607434db48364a5cdab3020bd7e315ed2662a3b35b5f;

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_0_1_2 =
        address(0xeaD68E489Cb19453b294dc46a3A5710b0d46d17F);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH_0_1_2 =
        0x4d94318cde48f1bc20f97e00aefad84bfb7c9db15c81b882862e127b05e06e15;

    /// @dev The corporate-actions facet. The receipt vault's `fallback()`
    /// hardcodes this address and delegatecalls every non-matching selector
    /// here, so a facet bytecode change forces a vault impl redeploy too. With
    /// the new rain.vats tag the receipt vault impl is rebuilt, so this facet
    /// is rebuilt in lock-step.
    address constant STOX_CORPORATE_ACTIONS_FACET_0_1_2 = address(0x51f78B77EdffDB62b8AeB753066C318a46D05D74);
    bytes32 constant STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_2 =
        0x2a67c52129dff74d956bb7dcde1aac598c28dd29685237aca56dccb1d49bd6f8;

    /// @dev The `ST0xOrchestrator` implementation contract. Parameterless
    /// (Initializable) — deployed once via Zoltu and pointed at by the beacon
    /// inside `ST0xOrchestratorBeaconSetDeployer`. Per-token orchestrators are
    /// `BeaconProxy` clones minted by that beacon deployer.
    address constant ST0X_ORCHESTRATOR_0_1_2 = address(0x77ab9b240caC5F37a5D4d51651936ea1d61DF1A2);
    bytes32 constant ST0X_ORCHESTRATOR_CODEHASH_0_1_2 =
        0xf05134e6b0ac1a88a8ba69eba472e651ee204c60914782543bcf339bcf273b7a;

    /// @dev `ST0xOrchestratorBeaconSetDeployer` — the Zoltu-deployable concrete
    /// deployer with `BEACON_INITIAL_OWNER` and the impl above baked in (no
    /// subclass; its logic is local to this repo). Anyone can call
    /// `deploy(owner)` to mint a `BeaconProxy`-cloned singleton orchestrator.
    address constant ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_2 = address(0xBd81E4B0992E6fA49812e341f917c05f5c97728d);
    bytes32 constant ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CODEHASH_0_1_2 =
        0x61d4098eb564665d48f4ca6fefa6396b6ecd3ff9cb72df7760f06e80ca56292b;

    /// @notice The V4 production authoriser clone — an EIP-1167 minimal
    /// proxy of `STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1`
    /// that the upgrade script `setAuthorizer`s every production receipt
    /// vault onto, replacing the current pre-V3 clone pinned in
    /// `LibAuthoriserInvariants.STOX_PROD_AUTHORISER`.
    ///
    /// **PLACEHOLDER** (`address(0)` literal) until the clone is deployed
    /// against the V4 impl as a one-off ops step (initialised with the
    /// ST0x token-owner Safe as `initialAdmin`, then the non-admin grants
    /// from `LibAuthoriserInvariants.expectedGrants()` are mirrored onto
    /// it). The clone's address is not deterministic ahead of time (Rain
    /// `CloneFactory` uses non-deterministic `Clones.clone`); the
    /// post-deploy edit hand-writes the real literal in place of
    /// `address(0)` here.
    ///
    /// Lives in this lib (the deploy artifacts pin) rather than in
    /// `LibAuthoriserInvariants` because it's a deploy target, not a
    /// current-state invariant. Post-swap, `LibAuthoriserInvariants.STOX_PROD_AUTHORISER`
    /// updates to this address; the constant here is the immutable
    /// historical record of the V4 artifact.
    address constant STOX_PROD_AUTHORISER_V4_CLONE = address(0);

    /// @notice The pinned EIP-1167 runtime codehash for
    /// `STOX_PROD_AUTHORISER_V4_CLONE`. Deterministic from the V4 impl
    /// address embedded in the minimal-proxy runtime
    /// (`363d3d373d3d3d363d73<impl>5af43d82803e903d91602b57fd5bf3`); the
    /// invariant uses it to prove the clone hasn't been etched over.
    ///
    /// **PLACEHOLDER** — fill in once the V4 impl address is known and the
    /// clone is deployed. Easiest path: compute via
    /// `keccak256(abi.encodePacked(hex"363d3d373d3d3d363d73", v4Impl, hex"5af43d82803e903d91602b57fd5bf3"))`.
    bytes32 constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH = bytes32(0);

    // =========================================================================
    // Per-release creation + runtime bytecode (frozen historicals).
    //
    // Aliased from the per-release pointer snapshots: 0.1.1 from
    // `src/generated/0_1_1/` (frozen at that release), 0.1.2 from the current
    // `src/generated/` set. When a future release changes a contract, the older
    // release keeps the exact bytecode it shipped — the address + codehash pin
    // the identity, these pin the bytecode for reproducible verification.
    // =========================================================================

    bytes constant STOX_RECEIPT_CREATION_CODE_0_1_1 = STOX_RECEIPT_CREATION_0_1_1_GEN;
    bytes constant STOX_RECEIPT_RUNTIME_CODE_0_1_1 = STOX_RECEIPT_RUNTIME_0_1_1_GEN;
    bytes constant STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1 = STOX_RECEIPT_VAULT_CREATION_0_1_1_GEN;
    bytes constant STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_1 = STOX_RECEIPT_VAULT_RUNTIME_0_1_1_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE_0_1_1 = STOX_WRAPPED_TOKEN_VAULT_CREATION_0_1_1_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_0_1_1 = STOX_WRAPPED_TOKEN_VAULT_RUNTIME_0_1_1_GEN;
    bytes constant STOX_UNIFIED_DEPLOYER_CREATION_CODE_0_1_1 = STOX_UNIFIED_DEPLOYER_CREATION_0_1_1_GEN;
    bytes constant STOX_UNIFIED_DEPLOYER_RUNTIME_CODE_0_1_1 = STOX_UNIFIED_DEPLOYER_RUNTIME_0_1_1_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_0_1_1 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_0_1_1_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_0_1_1 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_0_1_1_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_1_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_1_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_1_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_1 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_1_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_CODE_0_1_1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_0_1_1_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_0_1_1_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_CODE_0_1_1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_0_1_1_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE_0_1_1 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_0_1_1_GEN;
    bytes constant STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_0_1_1 = STOX_CORPORATE_ACTIONS_FACET_CREATION_0_1_1_GEN;
    bytes constant STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_1 = STOX_CORPORATE_ACTIONS_FACET_RUNTIME_0_1_1_GEN;

    bytes constant STOX_RECEIPT_CREATION_CODE_0_1_2 = STOX_RECEIPT_CREATION_0_1_2_GEN;
    bytes constant STOX_RECEIPT_RUNTIME_CODE_0_1_2 = STOX_RECEIPT_RUNTIME_0_1_2_GEN;
    bytes constant STOX_RECEIPT_VAULT_CREATION_CODE_0_1_2 = STOX_RECEIPT_VAULT_CREATION_0_1_2_GEN;
    bytes constant STOX_RECEIPT_VAULT_RUNTIME_CODE_0_1_2 = STOX_RECEIPT_VAULT_RUNTIME_0_1_2_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE_0_1_2 = STOX_WRAPPED_TOKEN_VAULT_CREATION_0_1_2_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE_0_1_2 = STOX_WRAPPED_TOKEN_VAULT_RUNTIME_0_1_2_GEN;
    bytes constant STOX_UNIFIED_DEPLOYER_CREATION_CODE_0_1_2 = STOX_UNIFIED_DEPLOYER_CREATION_0_1_2_GEN;
    bytes constant STOX_UNIFIED_DEPLOYER_RUNTIME_CODE_0_1_2 = STOX_UNIFIED_DEPLOYER_RUNTIME_0_1_2_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_0_1_2 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_0_1_2_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_CODE_0_1_2 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_RUNTIME_0_1_2_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_2 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_2_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_2 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_2_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_2 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_0_1_2_GEN;
    bytes constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_2 =
        STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RUNTIME_0_1_2_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_CODE_0_1_2 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_0_1_2_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_CODE_0_1_2 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RUNTIME_0_1_2_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_CODE_0_1_2 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_0_1_2_GEN;
    bytes constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE_0_1_2 =
        STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_0_1_2_GEN;
    bytes constant STOX_CORPORATE_ACTIONS_FACET_CREATION_CODE_0_1_2 = STOX_CORPORATE_ACTIONS_FACET_CREATION_0_1_2_GEN;
    bytes constant STOX_CORPORATE_ACTIONS_FACET_RUNTIME_CODE_0_1_2 = STOX_CORPORATE_ACTIONS_FACET_RUNTIME_0_1_2_GEN;
    bytes constant ST0X_ORCHESTRATOR_CREATION_CODE_0_1_2 = ST0X_ORCHESTRATOR_CREATION_0_1_2_GEN;
    bytes constant ST0X_ORCHESTRATOR_RUNTIME_CODE_0_1_2 = ST0X_ORCHESTRATOR_RUNTIME_0_1_2_GEN;
    bytes constant ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_2 =
        ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_0_1_2_GEN;
    bytes constant ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_RUNTIME_CODE_0_1_2 =
        ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_RUNTIME_0_1_2_GEN;
}
