// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

/// @notice The canonical Safe v1.4.1 proxy factory, at its deterministic
/// address on every chain Safe supports. Mirrored as a two-selector interface
/// here because no dependency in this repo carries the Safe factory ABI.
interface ISafeProxyFactory {
    /// @notice Deploy a proxy at `CREATE2(keccak256(keccak256(initializer) ++
    /// saltNonce))` over the proxy creation code appended with `singleton`,
    /// then run `initializer` on it. Permissionless: the sender is not part of
    /// the address derivation.
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
    /// @notice The proxy creation code the factory deploys.
    function proxyCreationCode() external pure returns (bytes memory);
}

/// @notice The active chain's Safe pin already has code: the Safe exists and
/// there is nothing to create (a re-dispatch), or something else occupies the
/// address (resolve by hand).
/// @param safe The pinned address.
error TokenOwnerSafeAlreadyExists(address safe);

/// @notice The address the canonical initializer derives to on this chain is
/// not the chain's Safe pin. The pin is for a Safe created some other way
/// (Base's was), or the pin is wrong; either way this script must not create
/// a stray Safe.
/// @param pinned The chain's pinned Safe.
/// @param derived The address the replay would land on.
error TokenOwnerSafePinNotDerivable(address pinned, address derived);

/// @notice The factory reported a different proxy address than the one it was
/// asked to derive — the factory at the canonical address is not the v1.4.1
/// factory this replay was computed against.
/// @param expected The derived address.
/// @param actual The address the factory returned.
error TokenOwnerSafeLandedElsewhere(address expected, address actual);

/// @title CreateTokenOwnerSafe
/// @notice Creates the ST0x token-owner Safe on a freshly onboarded chain at
/// its pinned address, by replaying the exact `createProxyWithNonce` call that
/// created the Ethereum Safe (tx `0x8825d68e…da39`, 2026-07-16): the canonical
/// v1.4.1 proxy factory, the L1 `Safe` singleton, `Safe.setup` over the six
/// owners at threshold 1 with the `SafeToL2Setup` migration delegatecall and
/// the compatibility fallback handler, salt nonce 0. The proxy address is a
/// pure function of that initializer and the factory, never of the sender, so
/// the CI deploy key can dispatch this on any chain and land the same
/// `0x3840aeDa…0329` the Ethereum and HyperEVM Safes occupy.
///
/// @dev Base's Safe was created some other way and sits elsewhere, so Base is
/// refused. The Safe is left at threshold 1 because the threshold is part of
/// the initializer and therefore of the address; an owner raises it to the
/// policy's 3 with `changeThreshold(3)` in the Safe UI. Every pin-dependent
/// step gates on the threshold, so nothing downstream runs in the 1-of-6
/// window.
contract CreateTokenOwnerSafe is Script {
    /// @notice Pre-flight (pin derivable, not yet created), broadcast the
    /// replay, assert the Safe landed at the pin with the policy's owner set,
    /// v1.4.1 identity and fallback handler, at the creation threshold.
    function run() external {
        address pinned = LibSafeInvariants.safeForChainId(block.chainid);
        address derived = LibSafeInvariants.expectedTokenOwnerSafeAddress();
        if (derived != pinned) revert TokenOwnerSafePinNotDerivable(pinned, derived);
        if (pinned.code.length != 0) revert TokenOwnerSafeAlreadyExists(pinned);
        LibSafeInvariants.assertCanonicalSafeContracts();

        console2.log("Creating the token-owner Safe on chain id", block.chainid);
        console2.log("at:", pinned);

        vm.startBroadcast();
        address created = ISafeProxyFactory(LibSafeInvariants.SAFE_V1_4_1_PROXY_FACTORY)
            .createProxyWithNonce(
                LibSafeInvariants.SAFE_V1_4_1_L1_SINGLETON,
                LibSafeInvariants.tokenOwnerSafeInitializer(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_SALT_NONCE
            );
        vm.stopBroadcast();
        if (created != pinned) revert TokenOwnerSafeLandedElsewhere(pinned, created);

        // Ordered: Safe stores owners in the order `setup` received them, so
        // this also proves the initializer's owner order landed byte-exact.
        LibSafeInvariants.assertAll(
            IGnosisSafe(pinned),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD,
            LibSafeInvariants.tokenOwnerSafeCreationOwners()
        );

        console2.log("Token-owner Safe created at the pin at threshold 1 of 6. An owner");
        console2.log("raises it to 3 (changeThreshold) before any pin-dependent dispatch.");
    }
}
