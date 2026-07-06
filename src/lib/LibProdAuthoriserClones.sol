// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @title LibProdAuthoriserClones
/// @notice Hand-maintained per-chain pins for the V4 authoriser clone.
/// @dev The V4 authoriser clone address is NON-deterministic — it is a
/// nonce-based `CloneFactory.clone()` of the deterministic V4 impl, so it
/// cannot be computed at build time and must be PROVIDED post-deployment.
/// It is therefore hand-maintained here (a placeholder `address(0)` until a
/// hydration PR fills the real literal), NOT emitted by `BuildPointers`
/// alongside the deterministic Zoltu pins. The Base clone lives in the
/// generated `LibProdDeployV4` for historical reasons; the ETHEREUM sibling
/// lives here so a new chain's clone pin never touches the generated files.
///
/// The codehash is shared across chains: the EIP-1167 minimal-proxy runtime
/// embeds only the implementation address, and the V4 authoriser impl sits
/// at the same deterministic Zoltu address on every chain, so
/// `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` is the expected
/// codehash for every chain's clone.
library LibProdAuthoriserClones {
    /// @notice The V4 production authoriser clone on Ethereum mainnet — the
    /// Ethereum sibling of the Base clone
    /// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`).
    ///
    /// **PLACEHOLDER** (`address(0)`) until the Ethereum bootstrap deploys
    /// the clone (script `20260706-deploy-v4-authoriser-clone-ethereum`,
    /// initialised with the Ethereum token-owner Safe from
    /// `LibChainPrincipals.ethereum()` as `initialAdmin`, then its non-admin
    /// grants mirrored). The clone address is not deterministic ahead of
    /// time; the post-deploy hydrate PR replaces this `address(0)` with the
    /// real literal — the same pin-before-modify gate as the Base clone.
    address internal constant STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM = address(0);

    /// @notice The shared EIP-1167 codehash for every chain's V4 authoriser
    /// clone. Re-exported from `LibProdDeployV4` so consumers of the Ethereum
    /// clone pin read the address and its expected codehash from one place.
    bytes32 internal constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH =
        LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;
}
