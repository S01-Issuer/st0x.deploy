// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {
    CreateTokenOwnerSafe,
    TokenOwnerSafeAlreadyExists,
    TokenOwnerSafePinNotDerivable
} from "../../script/20260910-create-token-owner-safe.s.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {CreateTokenOwnerSafeHarness} from "./CreateTokenOwnerSafeHarness.sol";

/// @title CreateTokenOwnerSafeTest
/// @notice The replayed initializer must derive to the address the live
/// Safes occupy (proving the reproduction is byte-exact), the script must
/// refuse every chain it must not touch, and on a fresh chain it must land
/// the Safe at the pin carrying the policy's owner set.
contract CreateTokenOwnerSafeTest is Test {
    /// @notice The derivation reproduces the Ethereum Safe's address — the
    /// creation this script replays — and HyperEVM's, which was created the
    /// same way. Both forks also prove the refusal to re-create.
    function testDerivationMatchesTheLiveSafes() external {
        CreateTokenOwnerSafeHarness harness = new CreateTokenOwnerSafeHarness();

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertEq(harness.callDerivedSafeAddress(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM, "ethereum");
        CreateTokenOwnerSafe script = new CreateTokenOwnerSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenOwnerSafeAlreadyExists.selector, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM
            )
        );
        script.run();

        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertEq(harness.callDerivedSafeAddress(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM, "hyperevm");
    }

    /// @notice Base's Safe was not created by this initializer (a different
    /// address), so the script refuses Base rather than creating a stray
    /// Safe there.
    function testRefusesBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
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

    /// @notice On a chain whose pin has no code yet, the replay lands the
    /// Safe at the pin with the policy's owner set, v1.4.1 identity and
    /// fallback handler, at the creation threshold of 1 — and a second run
    /// refuses. Exercised on whichever of the new chains is still bare; a
    /// chain whose Safe already exists proves the refusal instead.
    function testCreatesAtThePinOnAFreshChain() external {
        string[2] memory networks = [LibStoxDeployNetworks.ROBINHOOD, LibStoxDeployNetworks.BSC];
        address[2] memory pins =
            [LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC];
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            CreateTokenOwnerSafe script = new CreateTokenOwnerSafe();
            if (pins[i].code.length != 0) {
                vm.expectRevert(abi.encodeWithSelector(TokenOwnerSafeAlreadyExists.selector, pins[i]));
                script.run();
                continue;
            }
            script.run();
            IGnosisSafe safe = IGnosisSafe(pins[i]);
            assertGt(pins[i].code.length, 0, networks[i]);
            LibSafeInvariants.assertImmutableInvariants(safe);
            LibSafeInvariants.assertOwnerSetUnordered(safe, LibSafeInvariants.expectedOwners());
            assertEq(safe.getThreshold(), 1, "creation threshold");
            vm.expectRevert(abi.encodeWithSelector(TokenOwnerSafeAlreadyExists.selector, pins[i]));
            script.run();
        }
    }
}
