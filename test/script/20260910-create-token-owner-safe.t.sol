// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    CreateTokenOwnerSafe,
    ISafeProxyFactory,
    TokenOwnerSafeAlreadyExists,
    TokenOwnerSafePinNotDerivable
} from "../../script/20260910-create-token-owner-safe.s.sol";
import {LibSafeInvariants, SafeCanonicalContractCodehashMismatch} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title CreateTokenOwnerSafeTest
/// @notice The script must refuse every chain it must not touch, and on a
/// fresh chain it must land the Safe at the pin carrying the policy's owner
/// set. The derivation itself is pinned in `LibSafeInvariantsTest`.
contract CreateTokenOwnerSafeTest is Test {
    /// @notice The pinned init code hash is what the live factory CREATE2s
    /// over: its `proxyCreationCode()` with the L1 singleton appended.
    function testLiveFactoryCreationCodeHashesToThePin() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        bytes memory initCode = abi.encodePacked(
            ISafeProxyFactory(LibSafeInvariants.SAFE_V1_4_1_PROXY_FACTORY).proxyCreationCode(),
            uint256(uint160(LibSafeInvariants.SAFE_V1_4_1_L1_SINGLETON))
        );
        assertEq(keccak256(initCode), LibSafeInvariants.SAFE_V1_4_1_L1_PROXY_INITCODE_HASH);
    }

    /// @notice Base's Safe was not created by this initializer (a different
    /// address), so the script refuses Base rather than creating a stray
    /// Safe there.
    function testRefusesBase() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        // Code at the pin, so the refusal proves derivability is checked first.
        vm.etch(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, hex"FE");
        address derived = LibSafeInvariants.expectedTokenOwnerSafeAddress();
        CreateTokenOwnerSafe script = new CreateTokenOwnerSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenOwnerSafePinNotDerivable.selector, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, derived
            )
        );
        script.run();
    }

    /// @notice A derivable, unoccupied pin on a chain without the canonical
    /// Safe contracts is refused by the pre-flight, typed, before broadcasting.
    function testRefusesAChainWithoutTheCanonicalSafeContracts() external {
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        address factory = LibSafeInvariants.SAFE_V1_4_1_PROXY_FACTORY;
        CreateTokenOwnerSafe script = new CreateTokenOwnerSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCanonicalContractCodehashMismatch.selector,
                factory,
                LibSafeInvariants.SAFE_V1_4_1_PROXY_FACTORY_CODEHASH,
                factory.codehash
            )
        );
        script.run();
    }

    /// @notice The replay lands the Safe at the pin with the policy's owner
    /// set, v1.4.1 identity and fallback handler, at the creation threshold of
    /// 1, and a second run refuses. A chain whose Safe already exists first
    /// proves the refusal, then has the pin cleared on the fork so the creation
    /// path stays exercised against its live factory and singletons; Ethereum
    /// runs that branch today.
    function testCreatesAtThePinOnAFreshChain() external {
        string[3] memory networks =
            [LibStoxDeployNetworks.ETHEREUM, LibStoxDeployNetworks.ROBINHOOD, LibStoxDeployNetworks.BSC];
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            address pin = LibSafeInvariants.safeForChainId(block.chainid);
            CreateTokenOwnerSafe script = new CreateTokenOwnerSafe();
            if (pin.code.length != 0) {
                vm.expectRevert(abi.encodeWithSelector(TokenOwnerSafeAlreadyExists.selector, pin));
                script.run();
                vm.etch(pin, "");
                vm.resetNonce(pin);
            }
            script.run();
            assertGt(pin.code.length, 0, networks[i]);
            vm.expectRevert(abi.encodeWithSelector(TokenOwnerSafeAlreadyExists.selector, pin));
            script.run();
        }
    }
}
