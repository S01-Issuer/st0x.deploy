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
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20260910-create-token-owner-safe` and `network` set to the new
/// chain. Self-scoping: it derives the address from the initializer, refuses
/// unless that equals the chain's `LibSafeInvariants` pin (so it cannot create
/// a Safe the repo does not expect — Base's pin is not derivable this way and
/// is refused), and refuses if the pin already has code. It leaves the Safe at
/// threshold **1**, exactly as the replayed creation did, because the
/// threshold is part of the initializer and therefore of the address. Raising
/// it to the policy's 3-of-6 is an owner action: author it with
/// `MigrateMultisigThreshold` (`multisig-artifact.yaml`) and execute from any
/// one owner. Every pin-dependent step (`assertActiveChainTokenOwnerSafe`)
/// gates on the threshold, so nothing downstream can run against the 1-of-6
/// window.
contract CreateTokenOwnerSafe is Script {
    /// @notice Safe's fee collector, the `paymentReceiver` the Safe UI wrote
    /// into the Ethereum creation. Inert at `payment = 0`, but part of the
    /// initializer bytes and therefore of the address.
    address internal constant SAFE_PAYMENT_RECEIVER = 0x5afe7A11E7000000000000000000000000000000;
    /// @notice The threshold the replayed creation sets. NOT the policy's; see
    /// the contract NatSpec.
    uint256 internal constant CREATION_THRESHOLD = 1;
    /// @notice The salt nonce the Ethereum creation used.
    uint256 internal constant SALT_NONCE = 0;

    /// @notice The six owners in the order the Ethereum creation listed them.
    /// Order matters: it is part of the initializer bytes. The set is the
    /// policy set (`LibSafeInvariants.expectedOwners`, asserted below).
    /// @return owners The creation-order owner list.
    function creationOwners() internal pure returns (address[] memory owners) {
        owners = new address[](6);
        owners[0] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_5;
        owners[1] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_1;
        owners[2] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_2;
        owners[3] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_3;
        owners[4] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_4;
        owners[5] = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_6;
    }

    /// @notice The exact `Safe.setup` calldata of the Ethereum creation.
    /// @return The initializer bytes.
    function initializer() internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            creationOwners(),
            CREATION_THRESHOLD,
            LibSafeInvariants.SAFE_V1_4_1_TO_L2_SETUP,
            abi.encodeWithSignature("setupToL2(address)", LibSafeInvariants.SAFE_V1_4_1_L2_SINGLETON),
            LibSafeInvariants.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            address(0),
            uint256(0),
            SAFE_PAYMENT_RECEIVER
        );
    }

    /// @notice The address `createProxyWithNonce` derives for the initializer
    /// on every chain: the v1.4.1 factory's `CREATE2` over the pinned proxy
    /// init code (creation code ++ L1 singleton), salted with
    /// `keccak256(keccak256(initializer) ++ saltNonce)`.
    /// @return The derived proxy address.
    function derivedSafeAddress() internal pure returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer()), SALT_NONCE));
        return vm.computeCreate2Address(
            salt, LibSafeInvariants.SAFE_V1_4_1_L1_PROXY_INITCODE_HASH, LibSafeInvariants.SAFE_V1_4_1_PROXY_FACTORY
        );
    }

    /// @notice Pre-flight (pin derivable, not yet created), broadcast the
    /// replay, assert the Safe landed at the pin with the policy's owner set,
    /// v1.4.1 identity and fallback handler, at the creation threshold.
    function run() external {
        address pinned = LibSafeInvariants.safeForChainId(block.chainid);
        address derived = derivedSafeAddress();
        if (derived != pinned) revert TokenOwnerSafePinNotDerivable(pinned, derived);
        if (pinned.code.length != 0) revert TokenOwnerSafeAlreadyExists(pinned);
        LibSafeInvariants.assertCanonicalSafeContracts();

        console2.log("Creating the token-owner Safe on chain id", block.chainid);
        console2.log("at:", pinned);

        vm.startBroadcast();
        address created = ISafeProxyFactory(LibSafeInvariants.SAFE_V1_4_1_PROXY_FACTORY)
            .createProxyWithNonce(LibSafeInvariants.SAFE_V1_4_1_L1_SINGLETON, initializer(), SALT_NONCE);
        vm.stopBroadcast();
        if (created != pinned) revert TokenOwnerSafeLandedElsewhere(pinned, created);

        // Ordered: Safe stores owners in the order `setup` received them, so
        // this also proves the initializer's owner order landed byte-exact.
        LibSafeInvariants.assertAll(IGnosisSafe(pinned), CREATION_THRESHOLD, creationOwners());

        console2.log("Token-owner Safe created at the pin. Threshold is 1 of 6: raise it to");
        console2.log("3 via MigrateMultisigThreshold before any pin-dependent dispatch.");
    }
}
