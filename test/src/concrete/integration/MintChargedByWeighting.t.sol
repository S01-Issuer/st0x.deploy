// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {EvaluableV4, SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

import {MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV1.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title MintChargedByWeightingTest
/// @notice Workflow: the weighting's value charges the buckets, against the
/// real vault. The mint admin
/// sets a weighting that prices each mint at the lead's attested price, MM
/// mints two whole tokens of the real `tTEST` vault (18 decimals, read from
/// the vault itself) with an attestation at 150, and the recipient's bucket
/// is charged 300 — not `2e18` — while the vault delivers the `2e18` shares.
/// A second workflow has the weighting refuse an attestation for another
/// symbol, so the symbol the expression compares against is the vault's own.
contract MintChargedByWeightingTest is OrchestratorIntegrationTest {
    using LibDecimalFloat for Float;

    /// A capacity the value fits and the raw amount does not.
    Float internal immutable CAPACITY = LibDecimalFloat.packLossless(1000, 0);

    function _assertFloatEq(Float actual, Float expected, string memory err) internal pure {
        (int256 c, int256 e) = actual.unpack();
        assertTrue(actual.eq(expected), string.concat(err, ": got ", vm.toString(c), "e", vm.toString(e)));
    }

    /// The lead's attestation of `[attestedSymbol, price, now]`.
    function _lead(string memory attestedSymbol, int256 price) internal view returns (SignedContextV1[] memory) {
        SignedContextV1[] memory attestations = new SignedContextV1[](1);
        attestations[0] = attest(LEAD_KEY, symbol(attestedSymbol), float(price), float(int256(block.timestamp)));
        return attestations;
    }

    function testMintIsChargedTheWeightingValueAgainstTheRealVault() external {
        (address eoa, uint256 pk) = makeAddrAndKey("weighted-recipient");
        EvaluableV4 memory priced = _weighting("_: mul(mint-amount() lead-price());");
        vm.startPrank(OWNER);
        orchestrator.setRecipientMintLimit(eoa, CAPACITY, NO_LEAK);
        orchestrator.setMintWeighting(priced);
        vm.stopPrank();

        // The premises the charge rests on, read from the real vault.
        assertEq(vault.symbol(), "tTEST", "the vault's symbol");
        assertEq(vault.decimals(), 18, "the vault's decimals");
        uint256 amount = 2e18;
        assertTrue(
            LibDecimalFloat.fromFixedDecimalLosslessPacked(amount, 0).gt(CAPACITY),
            "premise: the raw amount does not fit the capacity"
        );

        bytes32 nonce = keccak256("weighted");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        SignedContextV1[] memory attestations = _lead("tTEST", 150);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "", attestations);

        assertEq(vault.balanceOf(eoa), amount, "the vault delivered the amount");
        assertEq(receipt.balanceOf(address(orchestrator), vault.highwaterId()), amount, "and kept the receipt");
        _assertFloatEq(orchestrator.mintHeadroom(MM, eoa), LibDecimalFloat.packLossless(700, 0), "charged 2 * 150");
    }

    function testMintRefusedByTheWeightingAgainstTheRealVault() external {
        (address eoa, uint256 pk) = makeAddrAndKey("refused-recipient");
        EvaluableV4 memory guarded = _weighting(
            ":ensure(binary-equal-to(lead-symbol() mint-symbol()) \"attested another symbol\"),\n"
            "_: mul(mint-amount() lead-price());"
        );
        vm.startPrank(OWNER);
        orchestrator.setRecipientMintLimit(eoa, CAPACITY, NO_LEAK);
        orchestrator.setMintWeighting(guarded);
        vm.stopPrank();

        uint256 amount = 2e18;
        bytes32 nonce = keccak256("refused");
        MintAuthV1 memory auth = _signedMintAuth(address(vault), eoa, amount, nonce, pk);
        SignedContextV1[] memory otherSymbol = _lead("tOTHER", 150);
        vm.expectRevert("attested another symbol");
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "", otherSymbol);
        assertEq(vault.balanceOf(eoa), 0, "nothing was minted");
        assertFalse(orchestrator.nonceUsed(eoa, nonce), "the authorisation was not consumed");

        // The same authorisation with an attestation for the vault's own
        // symbol goes through.
        SignedContextV1[] memory ownSymbol = _lead("tTEST", 150);
        vm.prank(MM);
        orchestrator.mint(address(vault), eoa, amount, auth, "", ownSymbol);
        assertEq(vault.balanceOf(eoa), amount, "the vault delivered the amount");
        _assertFloatEq(orchestrator.mintHeadroom(MM, eoa), LibDecimalFloat.packLossless(700, 0), "charged 2 * 150");
    }
}
