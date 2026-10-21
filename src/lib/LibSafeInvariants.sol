// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibSafe} from "rain-deploy-0.1.19-main/src/lib/LibSafe.sol";

/// @notice No ST0x token-owner Safe address is pinned for the active chain.
/// Deliberately a typed revert rather than a silent fallback to another
/// chain's Safe: authoring or asserting against the wrong chain's Safe is the
/// catastrophic failure this selector exists to prevent.
/// @param chainId The chain id with no pinned token-owner Safe.
error UnsupportedChainForTokenOwnerSafe(uint256 chainId);

/// @title LibSafeInvariants
/// @notice The ST0x token-owner Safe's pins — its address per chain, its
/// owners, its threshold and the initializer every factory-derived chain's
/// Safe was created from — and the policy assertion over them. Everything
/// generic to a Safe v1.4.1 (its identity, the canonical contracts, no
/// module, no guard, the fallback handler, owners and threshold reads) is
/// `rain-deploy`'s `LibSafe`; this library supplies the ST0x values.
library LibSafeInvariants {
    // =========================================================================
    // ST0x token-owner Safe current-state pins.
    // =========================================================================

    /// @notice Base mainnet chain id.
    uint256 internal constant BASE_CHAIN_ID = 8453;

    /// @notice Ethereum mainnet chain id.
    uint256 internal constant ETHEREUM_CHAIN_ID = 1;

    /// @notice HyperEVM mainnet chain id.
    uint256 internal constant HYPEREVM_CHAIN_ID = 999;

    /// @notice Robinhood Chain mainnet chain id.
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;

    /// @notice BNB Smart Chain mainnet chain id.
    uint256 internal constant BSC_CHAIN_ID = 56;

    /// @notice The ST0x token-owner Safe on **Base** (the reference chain).
    address internal constant STOX_TOKEN_OWNER_SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;

    /// @notice The ST0x token-owner Safe on **Ethereum mainnet**.
    ///
    /// A **distinct per-chain address** (the matched-address approach was
    /// abandoned): deployed out-of-band as a v1.4.1 Safe with the SAME owner
    /// set + threshold + policy as Base. The address is a per-chain deploy
    /// artifact, NOT a principal; the whole POLICY (owners, threshold, v1.4.1
    /// identity, fallback handler, no modules/guard) is the shared pin set, and
    /// this Safe is asserted against it — in every way that matters, now and
    /// into the future — by `assertTokenOwnerSafePolicy` (order-insensitive on the
    /// owner set; L1/L2-tolerant on the singleton, since a mainnet Safe runs
    /// the L1 `Safe` singleton while Base runs the L2 `SafeL2`).
    address internal constant STOX_TOKEN_OWNER_SAFE_ETHEREUM = 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329;

    /// @notice The ST0x token-owner Safe on **HyperEVM** (chain id 999).
    ///
    /// Deliberately the SAME address as Ethereum's Safe: created through the
    /// canonical Safe proxy factory with the same initializer, so the CREATE2
    /// address matches across chains. Still a per-chain deployment (its own
    /// proxy, its own state), asserted against the shared policy by
    /// `assertTokenOwnerSafePolicy` exactly like every other chain's Safe.
    address internal constant STOX_TOKEN_OWNER_SAFE_HYPEREVM = 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329;

    /// @notice The ST0x token-owner Safe on **Robinhood Chain** (chain id
    /// 4663).
    ///
    /// The SAME address as the Ethereum and HyperEVM Safes, for the same
    /// reason: created through the canonical Safe proxy factory
    /// (`0x4e1DCf7A…`, live on 4663 with the canonical codehash) with the
    /// identical initializer and salt nonce, so the CREATE2 address matches.
    /// A per-chain deployment with its own state, asserted against the shared
    /// policy by `assertTokenOwnerSafePolicy` like every other chain's Safe
    /// (`RobinhoodTokenOwnerSafeParityTest`).
    address internal constant STOX_TOKEN_OWNER_SAFE_ROBINHOOD = 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329;

    /// @notice The ST0x token-owner Safe on **BNB Smart Chain** (chain id
    /// 56). The same CREATE2 address again, for the same reason as Robinhood
    /// Chain's: canonical proxy factory, identical initializer and salt
    /// nonce (all of which are live on 56 with the canonical codehashes).
    /// Asserted against the shared policy by `BscTokenOwnerSafeParityTest`.
    address internal constant STOX_TOKEN_OWNER_SAFE_BSC = 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329;

    /// @notice The current expected threshold for `STOX_TOKEN_OWNER_SAFE`:
    /// 3-of-6 against the post-rotation owner roster. Scripts and the
    /// prod-state invariant pin treat this as the canonical current truth
    /// for the Safe's threshold.
    uint256 internal constant STOX_TOKEN_OWNER_SAFE_THRESHOLD = 3;

    /// @notice Owner #1 of `STOX_TOKEN_OWNER_SAFE`. Order matches
    /// `getOwners()` (Safe-internal linked-list order) against the
    /// post-rotation roster: `getOwners()` returns owners newest-first,
    /// so the last signer to be added via `addOwnerWithThreshold` appears
    /// at slot 0.
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_1 = 0x4746095B1Ea1A84446d34448f44e74D3d51f92F2;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_2 = 0xceC2cb8B8EE4000FFA3F8a7f8E0Fa0A3E3DAb72d;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_3 = 0x8D5901d8aE48101B59400235ad8614A2e0510466;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_4 = 0xC1C89b7f5448F447d59f920456A9610f6b2544bC;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_5 = 0xAB92b327c97A6E7461cBd76E2a789E5e106FF87e;
    address internal constant STOX_TOKEN_OWNER_SAFE_OWNER_6 = 0x5CCd3cE683b66ff271DDB8915fF528b8fcFa23c2;

    /// @notice Expected owner set for `STOX_TOKEN_OWNER_SAFE` in
    /// `getOwners()` order. Helper because Solidity 0.8 cannot express a
    /// file-scope `constant address[]`.
    function expectedOwners() internal pure returns (address[] memory) {
        address[] memory owners = new address[](6);
        owners[0] = STOX_TOKEN_OWNER_SAFE_OWNER_1;
        owners[1] = STOX_TOKEN_OWNER_SAFE_OWNER_2;
        owners[2] = STOX_TOKEN_OWNER_SAFE_OWNER_3;
        owners[3] = STOX_TOKEN_OWNER_SAFE_OWNER_4;
        owners[4] = STOX_TOKEN_OWNER_SAFE_OWNER_5;
        owners[5] = STOX_TOKEN_OWNER_SAFE_OWNER_6;
        return owners;
    }

    /// @notice The threshold the Ethereum creation set. Part of the initializer
    /// and therefore of the address; the policy's 3 is applied afterwards by
    /// the owners.
    uint256 internal constant STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD = 1;
    /// @notice The salt nonce the Ethereum creation used.
    uint256 internal constant STOX_TOKEN_OWNER_SAFE_CREATION_SALT_NONCE = 0;
    /// @notice Safe's fee collector, the `paymentReceiver` the Safe UI wrote
    /// into the Ethereum creation. Inert at `payment = 0`, but part of the
    /// initializer bytes and therefore of the address.
    address internal constant SAFE_PAYMENT_RECEIVER = 0x5afe7A11E7000000000000000000000000000000;

    /// @notice The six owners in the order the Ethereum creation listed them.
    /// Order is part of the initializer bytes; the set is `expectedOwners()`.
    function tokenOwnerSafeCreationOwners() internal pure returns (address[] memory) {
        address[] memory owners = new address[](6);
        owners[0] = STOX_TOKEN_OWNER_SAFE_OWNER_5;
        owners[1] = STOX_TOKEN_OWNER_SAFE_OWNER_1;
        owners[2] = STOX_TOKEN_OWNER_SAFE_OWNER_2;
        owners[3] = STOX_TOKEN_OWNER_SAFE_OWNER_3;
        owners[4] = STOX_TOKEN_OWNER_SAFE_OWNER_4;
        owners[5] = STOX_TOKEN_OWNER_SAFE_OWNER_6;
        return owners;
    }

    /// @notice The exact `Safe.setup` calldata of the Ethereum creation
    /// (tx 0x8825d68e…da39), which every factory-derived pin replays.
    function tokenOwnerSafeInitializer() internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            tokenOwnerSafeCreationOwners(),
            STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD,
            LibSafe.SAFE_V1_4_1_TO_L2_SETUP,
            abi.encodeWithSignature("setupToL2(address)", LibSafe.SAFE_V1_4_1_L2_SINGLETON),
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            address(0),
            uint256(0),
            SAFE_PAYMENT_RECEIVER
        );
    }

    /// @notice The address `createProxyWithNonce` derives for the initializer
    /// on every chain: the v1.4.1 factory's `CREATE2` over the pinned proxy
    /// init code, salted with `keccak256(keccak256(initializer) ++ saltNonce)`.
    /// Independent of the sender. Every factory-derived chain's pin equals
    /// this; Base's does not.
    function expectedTokenOwnerSafeAddress() internal pure returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(keccak256(tokenOwnerSafeInitializer()), STOX_TOKEN_OWNER_SAFE_CREATION_SALT_NONCE)
        );
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", LibSafe.SAFE_V1_4_1_PROXY_FACTORY, salt, LibSafe.SAFE_V1_4_1_L1_PROXY_INITCODE_HASH
                        )
                    )
                )
            )
        );
    }

    /// @notice The ST0x token-owner Safe address for the active chain, selected
    /// by chain id. The Safe address is a per-chain deploy artifact (the
    /// matched-address approach was abandoned), so consumers that must resolve
    /// "this chain's Safe" — the multichain production-state bundle, the
    /// cross-chain parity pin, the Ethereum token-authorise script — read it
    /// here. Reverts `UnsupportedChainForTokenOwnerSafe` for any chain without
    /// a pinned Safe rather than falling back to another chain's address.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return The chain's token-owner Safe.
    function safeForChainId(uint256 chainId) internal pure returns (address) {
        if (chainId == BASE_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE;
        }
        if (chainId == ETHEREUM_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE_ETHEREUM;
        }
        if (chainId == HYPEREVM_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE_HYPEREVM;
        }
        if (chainId == ROBINHOOD_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE_ROBINHOOD;
        }
        if (chainId == BSC_CHAIN_ID) {
            return STOX_TOKEN_OWNER_SAFE_BSC;
        }
        revert UnsupportedChainForTokenOwnerSafe(chainId);
    }

    /// @notice Assert a Safe carries the ST0x token-owner POLICY — the
    /// chain-agnostic truths pinned in this library: `LibSafe.assertLockedDown`
    /// (a genuine v1.4.1 Safe with no module, no guard and the canonical
    /// fallback handler), the pinned owner SET, and the pinned threshold. The
    /// policy is a property of the ORGANISATION, not of any chain: every
    /// chain's token-owner Safe — Base included — is asserted against the same
    /// pins. Only the Safe ADDRESS is per-chain (a deploy artifact, resolved by
    /// `safeForChainId`).
    /// @dev The owner check is order-INSENSITIVE (`LibSafe.assertOwnersAsSet`):
    /// `getOwners()` order is a Safe-internal linked-list artifact of the
    /// order owners were added on that chain's deploy/rotation, so order is
    /// not a policy property. If the policy ever changes, the pins move and
    /// every chain's Safe goes red until realigned — one source of truth,
    /// asserted everywhere, on every scheduled CI run.
    /// @param safe The Safe to validate against the pinned policy.
    function assertTokenOwnerSafePolicy(Safe safe) internal view {
        LibSafe.assertLockedDown(safe);
        LibSafe.assertOwnersAsSet(safe, expectedOwners());
        LibSafe.assertThreshold(safe, STOX_TOKEN_OWNER_SAFE_THRESHOLD);
    }

    /// @notice Resolve the active chain's token-owner Safe AND assert it
    /// carries the pinned chain-agnostic policy
    /// (`assertTokenOwnerSafePolicy`). No chain is special-cased: the policy
    /// is the shared truth and every chain's Safe is asserted against it
    /// identically. This is the single entry point a broadcast script's
    /// pre-flight and the scheduled CI pin both call, so the assertion that
    /// gates a manual broadcast is the identical one CI runs every commit — a
    /// broadcast can never revert on a Safe check CI has not already
    /// exercised on that chain.
    ///
    /// Reverts `UnsupportedChainForTokenOwnerSafe` (via `safeForChainId`) for a
    /// chain without a pinned Safe rather than silently asserting the wrong
    /// chain's Safe.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return The chain's token-owner Safe, proven in-policy.
    function assertActiveChainTokenOwnerSafe(uint256 chainId) internal view returns (address) {
        address safe = safeForChainId(chainId);
        assertTokenOwnerSafePolicy(Safe(payable(safe)));
        return safe;
    }
}
