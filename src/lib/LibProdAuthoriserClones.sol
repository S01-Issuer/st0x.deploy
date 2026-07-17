// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";

/// @notice No V4 authoriser clone pin is defined for the active chain.
/// Deliberately a typed revert rather than a silent fallback to another
/// chain's pin: reading the wrong chain's clone address is the catastrophic
/// failure this selector exists to prevent.
/// @param chainId The chain id with no defined clone pin.
error UnsupportedChainForAuthoriserClone(uint256 chainId);

/// @title LibProdAuthoriserClones
/// @notice Hand-maintained per-chain pins for the V4 authoriser clone — one
/// home for every chain's clone ADDRESS.
/// @dev The V4 authoriser clone address is NON-deterministic — it is a
/// nonce-based `CloneFactory.clone()` of the deterministic V4 impl, so it
/// cannot be computed at build time and must be PROVIDED post-deployment.
/// It is therefore hand-maintained here (a placeholder `address(0)` until a
/// hydration PR fills the real literal), NOT emitted by `BuildPointers`
/// alongside the deterministic Zoltu pins — `BuildPointers` provides only
/// the deterministic clone CODEHASH (below), never an address. Every chain's
/// clone pin lives here so the set never spreads across a hand-maintained
/// lib and the generated files.
///
/// The codehash is shared across chains and IS deterministic: the EIP-1167
/// minimal-proxy runtime embeds only the implementation address, and the V4
/// authoriser impl sits at the same deterministic Zoltu address on every
/// chain. It is therefore generated in `LibProdDeployV4` and re-exported
/// here so a consumer reads a chain's clone address and its expected
/// codehash from one place. Asserting each chain's live clone against this
/// single shared codehash is what proves the clone impls match across chains.
library LibProdAuthoriserClones {
    /// @notice The V4 production authoriser clone on Base.
    ///
    /// Deployed by the chain-agnostic `20260619-deploy-v4-authoriser-clone`.
    /// https://basescan.org/address/0x315b16faa6eE413faBCa877d3851B3818369f0cD
    /// @dev The Base vaults are swapped ONTO this clone by the separate V4
    /// receipt-vault upgrade; until that swap runs they still report the V3
    /// authoriser, so any strict "vault authoriser == this clone" assertion
    /// (e.g. the cross-chain parity token leg) is RED by design until the Base
    /// migration completes. `LibInvariants.assertAll` tolerates the window
    /// (V3 or clone until `V4_SWAP_DEADLINE`).
    address internal constant STOX_PROD_AUTHORISER_V4_CLONE_BASE = address(0x315b16faa6eE413faBCa877d3851B3818369f0cD);

    /// @notice The V4 production authoriser clone on Ethereum mainnet — the
    /// Ethereum sibling of `STOX_PROD_AUTHORISER_V4_CLONE_BASE`.
    ///
    /// **PLACEHOLDER** (`address(0)`) until the Ethereum bootstrap deploys
    /// the clone (chain-agnostic script `20260619-deploy-v4-authoriser-clone`
    /// run against Ethereum, initialised with the shared token-owner Safe as
    /// `initialAdmin`, then its non-admin grants mirrored). The clone address
    /// is not deterministic ahead of time; the post-deploy hydrate PR
    /// replaces this `address(0)` with the real literal — the same
    /// pin-before-modify gate as the Base clone.
    address internal constant STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM = address(0);

    /// @notice The shared EIP-1167 codehash for every chain's V4 authoriser
    /// clone. Re-exported from the generated `LibProdDeployV4` (where it is
    /// derived from the deterministic V4 impl) so consumers of any chain's
    /// clone pin read the address and its expected codehash from one place.
    bytes32 internal constant STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH =
        LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH;

    /// @notice Base mainnet chain id.
    uint256 internal constant BASE_CHAIN_ID = 8453;

    /// @notice Ethereum mainnet chain id.
    uint256 internal constant ETHEREUM_CHAIN_ID = 1;

    /// @notice The V4 authoriser clone pin for the active chain, selected by
    /// chain id — for the chain-agnostic clone-deploy script, which reads the
    /// pin for whatever network it is broadcast against (`block.chainid`).
    /// Reverts `UnsupportedChainForAuthoriserClone` for any chain without a
    /// defined pin rather than falling back to another chain's clone. Chain-
    /// specific consumers (Base migration scripts / invariants) reference the
    /// per-chain constant directly instead of this selector.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return clone The chain's V4 authoriser clone pin (`address(0)` until
    /// hydrated).
    function cloneForChainId(uint256 chainId) internal pure returns (address clone) {
        if (chainId == BASE_CHAIN_ID) {
            return STOX_PROD_AUTHORISER_V4_CLONE_BASE;
        }
        if (chainId == ETHEREUM_CHAIN_ID) {
            return STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        }
        revert UnsupportedChainForAuthoriserClone(chainId);
    }
}
