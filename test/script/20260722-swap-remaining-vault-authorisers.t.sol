// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";

import {
    SwapRemainingVaultAuthorisers,
    NoVaultsLeftToSwap,
    UnexpectedVaultAuthoriser
} from "../../script/20260722-swap-remaining-vault-authorisers.s.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title SwapRemainingVaultAuthorisersTest
/// @notice Live-fork coverage for the follow-up authoriser swap authoring.
/// The script is self-scoping (targets = every production vault still on the
/// V3 authoriser, read live), so these tests derive the same target set from
/// the fork before driving `run()` and assert the authored bundle matches it
/// exactly — the same assertion a signer makes when reviewing the artifact.
/// @dev Uses an unpinned Base head fork so the tests track live state: while
/// un-swapped vaults exist the happy path authors a bundle covering exactly
/// them; once the batch EXECUTES on-chain the target set is empty, the happy
/// path flips red on `NoVaultsLeftToSwap`, and the post-execution pin PR
/// retires it (the inverted guards keep covering the error paths).
contract SwapRemainingVaultAuthorisersTest is Test {
    SwapRemainingVaultAuthorisers internal script;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new SwapRemainingVaultAuthorisers();
    }

    /// @notice The still-V3 vaults, derived from the live fork exactly the
    /// way the script's `_selectTargets` does — the test-side replica the
    /// authored bundle is checked against.
    function liveV3Vaults() internal view returns (address[] memory targets) {
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        address[] memory candidates = new address[](vaults.length);
        uint256 count = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (address(IAuthorizableV1(vaults[i]).authorizer()) == LibAuthoriserInvariants.STOX_PROD_AUTHORISER) {
                candidates[count] = vaults[i];
                count++;
            }
        }
        targets = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            targets[i] = candidates[i];
        }
    }

    /// @notice Happy path against live Base state: `run()` completes —
    /// pre-flight, bundle build, simulation, strict uniform post-state,
    /// artifact, n+1 — and the artifact carries exactly one tx per still-V3
    /// vault, each targeting that vault. Red once the batch executes
    /// on-chain (`NoVaultsLeftToSwap`); retire in the post-execution pin PR.
    function testRunCompletesAndWritesArtifact() external {
        selectBaseFork();
        address[] memory expectedTargets = liveV3Vaults();
        assertTrue(expectedTargets.length > 0, "no un-swapped vaults left - retire this test (batch executed)");

        script.run();

        string memory json = vm.readFile("out/20260722-authoriser-swap.json");
        assertEq(
            vm.parseJsonString(json, ".meta.name"),
            "ST0x authoriser swap: remaining vaults onto the V4 clone",
            "artifact bundle name"
        );
        for (uint256 i = 0; i < expectedTargets.length; i++) {
            assertEq(
                vm.parseJsonAddress(json, string.concat(".transactions[", vm.toString(i), "].to")),
                expectedTargets[i],
                "bundle tx target mismatch"
            );
        }
        assertFalse(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(expectedTargets.length), "].to")),
            "no extra txs"
        );
    }

    /// @notice `run()` reverts `NoVaultsLeftToSwap` when the whole table is
    /// already on the V4 clone. Simulated by mocking every still-V3 vault's
    /// `authorizer()` to the clone — the exact post-execution state, so this
    /// also documents how the happy path dies once the batch lands.
    function testRunRevertsWhenNothingLeftToSwap() external {
        selectBaseFork();
        address[] memory targets = liveV3Vaults();
        for (uint256 i = 0; i < targets.length; i++) {
            vm.mockCall(
                targets[i],
                abi.encodeWithSelector(IAuthorizableV1.authorizer.selector),
                abi.encode(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE)
            );
        }
        vm.expectRevert(NoVaultsLeftToSwap.selector);
        script.run();
    }

    /// @notice `run()` reverts `UnexpectedVaultAuthoriser` when any
    /// production vault reports an authoriser that is neither V3 nor the V4
    /// clone — unknown drift must abort the authoring, never be papered over
    /// with a blind `setAuthorizer`.
    function testRunRejectsUnknownAuthoriser() external {
        selectBaseFork();
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();
        address victim = vaults[0];
        address rogue = makeAddr("rogueAuthoriser");
        vm.mockCall(victim, abi.encodeWithSelector(IAuthorizableV1.authorizer.selector), abi.encode(rogue));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedVaultAuthoriser.selector, victim, rogue));
        script.run();
    }
}
