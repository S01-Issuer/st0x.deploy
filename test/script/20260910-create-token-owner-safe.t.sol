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
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {CreateTokenOwnerSafeHarness} from "./CreateTokenOwnerSafeHarness.sol";

/// @title CreateTokenOwnerSafeTest
/// @notice The replayed initializer must derive to the address the live
/// Safes occupy (proving the reproduction is byte-exact), the script must
/// refuse every chain it must not touch, and on a fresh chain it must land
/// the Safe at the pin carrying the policy's owner set.
contract CreateTokenOwnerSafeTest is Test {
    /// @notice The derivation reproduces the pin of every factory-created Safe
    /// (Ethereum, the creation this script replays, and the chains created the
    /// same way) and not Base's. Fork-free: constants in, constants out.
    function testDerivationMatchesThePins() external {
        CreateTokenOwnerSafeHarness harness = new CreateTokenOwnerSafeHarness();
        address derived = harness.callDerivedSafeAddress();
        assertEq(derived, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM, "ethereum");
        assertEq(derived, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM, "hyperevm");
        assertEq(derived, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD, "robinhood");
        assertEq(derived, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC, "bsc");
        assertNotEq(derived, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "base");
    }

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
        CreateTokenOwnerSafeHarness harness = new CreateTokenOwnerSafeHarness();
        address derived = harness.callDerivedSafeAddress();
        assertNotEq(derived, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "Base pin is not this derivation");
        CreateTokenOwnerSafe script = new CreateTokenOwnerSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenOwnerSafePinNotDerivable.selector, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, derived
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
