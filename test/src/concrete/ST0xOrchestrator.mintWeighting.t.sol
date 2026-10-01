// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {LeakyBucketZeroAmount, LeakyBucketNegativeAmount} from "rain-lib-leakybucket-0.4.1/src/lib/LibLeakyBucket.sol";
import {
    IInterpreterCallerV4,
    EvaluableV4,
    SignedContextV1
} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";
import {StateNamespace} from "rainlang-interface-0.2.9/src/interface/IInterpreterStoreV3.sol";
import {LibNamespace} from "rainlang-interface-0.2.9/src/lib/ns/LibNamespace.sol";
import {InvalidSignature} from "rainlang-interface-0.2.9/src/lib/caller/LibContext.sol";

import {IST0xOrchestratorV1, MintAuthV1, Digest} from "src/interface/IST0xOrchestratorV1.sol";
import {LibSt0xAttestContext} from "src/lib/LibSt0xAttestContext.sol";
import {ST0xOrchestratorMintWeightingFixture} from "test/src/concrete/ST0xOrchestratorMintWeightingFixture.sol";

/// @title ST0xOrchestratorMintWeightingTest
/// @notice The value the Rainlang weighting produces is what fills the
/// mint-cap buckets, in place of the raw token amount. Every mint
/// here goes through the test Rainlang `St0xAttestSubParserTest` binds, with
/// the attest subparser beside it, over the token
/// `ST0xOrchestratorMintWeightingFixture` mocks as `tAAPL`.
contract ST0xOrchestratorMintWeightingTest is ST0xOrchestratorMintWeightingFixture {
    using LibDecimalFloat for Float;

    /// What the token answers `symbol()` with.
    string internal constant TOKEN_SYMBOL = "tAAPL";

    /// @inheritdoc ST0xOrchestratorMintWeightingFixture
    function tokenSymbol() internal pure override returns (string memory) {
        return TOKEN_SYMBOL;
    }

    // ------------------------------------------------------------------ //
    //                          Setting the weighting                     //
    // ------------------------------------------------------------------ //

    /// A fresh orchestrator has no weighting: a zero interpreter, store and
    /// bytecode.
    function testMintWeightingStartsUnset() external view {
        EvaluableV4 memory unset = orchestrator.mintWeighting();
        assertEq(address(unset.interpreter), address(0), "interpreter");
        assertEq(address(unset.store), address(0), "store");
        assertEq(unset.bytecode.length, 0, "bytecode");
    }

    /// Only `MINT_ADMIN_ROLE` sets the weighting.
    function testFuzzSetMintWeightingUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_ADMIN_ROLE(), caller));
        EvaluableV4 memory evaluable = _weighting(PRICED);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setMintWeighting(evaluable);
    }

    /// Setting the weighting emits it and stores it whole, and setting it
    /// again replaces it.
    function testSetMintWeightingEmitsAndReads() external {
        EvaluableV4 memory evaluable = _weighting(PRICED);
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.MintWeightingSet(OWNER, evaluable);
        vm.prank(OWNER);
        orchestrator.setMintWeighting(evaluable);

        EvaluableV4 memory stored = orchestrator.mintWeighting();
        assertEq(address(stored.interpreter), address(I_INTERPRETER), "interpreter");
        assertEq(address(stored.store), address(I_STORE), "store");
        assertEq(stored.bytecode, evaluable.bytecode, "bytecode");

        EvaluableV4 memory replacement = _setWeighting("_: mint-amount();");
        stored = orchestrator.mintWeighting();
        assertEq(stored.bytecode, replacement.bytecode, "replaced bytecode");
        assertNotEq(stored.bytecode, evaluable.bytecode, "the old bytecode is gone");
    }

    // ------------------------------------------------------------------ //
    //                          Refusals by name                          //
    // ------------------------------------------------------------------ //

    /// With both limits set and no weighting, there is nothing to charge the
    /// buckets with and the mint is refused by name.
    function testMintWeightingUnsetReverts() external {
        _setLimits(CAPACITY, CAPACITY);
        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);
        _mockVaultMint(AMOUNT);
        vm.expectRevert(IST0xOrchestratorV1.MintWeightingUnset.selector);
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("unset"), signature: ""}), "", attestations
        );
    }

    /// An unset limit is refused before the weighting is consulted: with no
    /// weighting either, the error still names the limit.
    function testUnsetLimitIsRefusedBeforeTheWeighting() external {
        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);
        _mockVaultMint(AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.MinterGlobalMintLimitUnset.selector, MINTER));
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("a"), signature: ""}), "", attestations
        );

        vm.prank(OWNER);
        orchestrator.setMinterGlobalMintLimit(MINTER, CAPACITY, NO_LEAK);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.RecipientMintLimitUnset.selector, address(recipient))
        );
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("b"), signature: ""}), "", attestations
        );
    }

    /// A weighting that leaves nothing on its stack has no charge to give.
    function testMintWeightingNoOutputsReverts() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting(":ensure(1 \"x\");");
        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);
        _mockVaultMint(AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.UnsupportedMintWeightingOutputs.selector, 0));
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("none"), signature: ""}), "", attestations
        );
    }

    /// A weighting of zero is a zero charge, which the bucket refuses.
    function testMintWeightingZeroIsRefusedByTheBucket() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting("_: 0;");
        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);
        _mockVaultMint(AMOUNT);
        vm.expectRevert(LeakyBucketZeroAmount.selector);
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("zero"), signature: ""}), "", attestations
        );
    }

    /// A negative weighting is a negative charge, which the bucket refuses,
    /// naming the charge.
    function testMintWeightingNegativeIsRefusedByTheBucket() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting("_: sub(0 1);");
        bytes memory reason = _mintReverts(AMOUNT, keccak256("negative"), _lead(TOKEN_SYMBOL, PRICE));
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes32(bytes4(reason)), bytes32(LeakyBucketNegativeAmount.selector), "selector");
        bytes memory args = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            args[i] = reason[i + 4];
        }
        _assertFloatEq(Float.wrap(abi.decode(args, (bytes32))), _f(-1, 0), "the carried charge");
        _assertFloatEq(_headroom(), CAPACITY, "nothing was charged");
    }

    /// The expression decides what the attestations must say: a failed
    /// `ensure` is a refused mint, with the expression's own reason.
    function testMintWeightingEnsureRevertsWithItsReason() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting(
            string.concat(
                ":ensure(binary-equal-to(lead-symbol() mint-symbol()) \"attested another symbol\"),\n", PRICED
            )
        );
        SignedContextV1[] memory otherSymbol = _lead("tMSFT", PRICE);
        _mockVaultMint(AMOUNT);
        vm.expectRevert("attested another symbol");
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("msft"), signature: ""}), "", otherSymbol
        );
        _assertFloatEq(_headroom(), CAPACITY, "nothing was charged");

        // Control: the same weighting over an attestation for the token's
        // own symbol passes, and the charge is the value.
        _mint(AMOUNT, keccak256("aapl"), _lead(TOKEN_SYMBOL, PRICE));
        _assertFloatEq(_headroom(), CAPACITY.sub(_f(VALUE, 0)), "charged the value");
    }

    /// An attestation whose signed values were changed after signing is
    /// refused when the grid is built, before the expression runs, naming
    /// which one.
    function testMintTamperedAttestationReverts() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting(PRICED);

        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);
        attestations[0].context[1] = float(PRICE + 1);
        _mockVaultMint(AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, 0));
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN,
            address(recipient),
            AMOUNT,
            MintAuthV1({nonce: keccak256("tampered"), signature: ""}),
            "",
            attestations
        );

        // A second attestation, tampered with, is named by its index.
        SignedContextV1[] memory two = new SignedContextV1[](2);
        two[0] = _lead(TOKEN_SYMBOL, PRICE)[0];
        two[1] = attest(OPERATOR_KEY_0, symbol(TOKEN_SYMBOL), float(PRICE), float(int256(block.timestamp)));
        two[1].signature[0] = two[1].signature[0] ^ bytes1(0xff);
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, 1));
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("tampered-1"), signature: ""}), "", two
        );
        _assertFloatEq(_headroom(), CAPACITY, "nothing was charged");
    }

    // ------------------------------------------------------------------ //
    //                  The value is the charge, not the amount           //
    // ------------------------------------------------------------------ //

    /// Two whole tokens at a lead price of 150 fill the buckets by 300. The
    /// raw amount, `2e18`, does not fit the capacity of 1000, so the mint
    /// going through shows the amount never reached the buckets; a second
    /// mint at a different price is charged a different value for the same
    /// amount.
    function testMintIsChargedTheWeightingValueNotTheAmount() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting(PRICED);
        assertTrue(
            LibDecimalFloat.fromFixedDecimalLosslessPacked(AMOUNT, 0).gt(CAPACITY),
            "premise: the raw amount does not fit the capacity"
        );
        _assertFloatEq(_headroom(), CAPACITY, "a fresh bucket offers its capacity");

        _mint(AMOUNT, keccak256("first"), _lead(TOKEN_SYMBOL, PRICE));
        _assertFloatEq(_headroom(), _f(1000 - VALUE, 0), "charged 2 * 150");

        _mint(AMOUNT, keccak256("second"), _lead(TOKEN_SYMBOL, 100));
        _assertFloatEq(_headroom(), _f(1000 - VALUE - 200, 0), "charged 2 * 100 for the same amount");
    }

    /// The recipient's cap-exceeded error carries the value as the charge.
    function testRecipientCapExceededCarriesTheWeightingValue() external {
        Float capacity = _f(500, 0);
        _setLimits(UNBOUNDED_CAPACITY, capacity);
        _setWeighting(PRICED);
        _mint(AMOUNT, keccak256("fits"), _lead(TOKEN_SYMBOL, PRICE));

        bytes memory reason = _mintReverts(AMOUNT, keccak256("over"), _lead(TOKEN_SYMBOL, PRICE));
        (address who, Float carriedCapacity, Float headroom, Float charge) =
            _decodeCapExceeded(reason, IST0xOrchestratorV1.RecipientMintCapExceeded.selector);
        assertEq(who, address(recipient), "recipient");
        _assertFloatEq(carriedCapacity, capacity, "capacity");
        _assertFloatEq(headroom, _f(500 - VALUE, 0), "headroom after one mint");
        _assertFloatEq(charge, _f(VALUE, 0), "the charge is the value");
    }

    /// And the minter's.
    function testMinterCapExceededCarriesTheWeightingValue() external {
        Float capacity = _f(500, 0);
        _setLimits(capacity, UNBOUNDED_CAPACITY);
        _setWeighting(PRICED);
        _mint(AMOUNT, keccak256("fits"), _lead(TOKEN_SYMBOL, PRICE));

        bytes memory reason = _mintReverts(AMOUNT, keccak256("over"), _lead(TOKEN_SYMBOL, PRICE));
        (address who, Float carriedCapacity, Float headroom, Float charge) =
            _decodeCapExceeded(reason, IST0xOrchestratorV1.MinterGlobalMintCapExceeded.selector);
        assertEq(who, MINTER, "minter");
        _assertFloatEq(carriedCapacity, capacity, "capacity");
        _assertFloatEq(headroom, _f(500 - VALUE, 0), "headroom after one mint");
        _assertFloatEq(charge, _f(VALUE, 0), "the charge is the value");
    }

    /// `mint-amount()` is the amount in whole tokens per the token's own
    /// `decimals()`: `2.5e18` units of an 18-decimals token is `2.5`.
    function testMintAmountIsInWholeTokens() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting("_: mint-amount();");
        _mint(2.5e18, keccak256("whole"), new SignedContextV1[](0));
        _assertFloatEq(_headroom(), _f(9975, -1), "charged 2.5");
    }

    /// The last output is the charge, whatever else the expression leaves.
    function testMintWeightingLastOutputIsTheCharge() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting("_ _: mint-amount() 7;");
        _mint(AMOUNT, keccak256("last"), new SignedContextV1[](0));
        _assertFloatEq(_headroom(), _f(1000 - 7, 0), "charged the last output");
    }

    /// The expression sees the grid `LibSt0xAttestContext` builds for this
    /// mint — the token's symbol, the amount in whole tokens, then the
    /// attestations — and the orchestrator emits it as `ContextV2`.
    function testMintEmitsTheContextTheWeightingSees() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting(PRICED);
        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);
        bytes32[][] memory grid = LibSt0xAttestContext.build(
            symbol(TOKEN_SYMBOL),
            Float.unwrap(LibDecimalFloat.fromFixedDecimalLosslessPacked(AMOUNT, TOKEN_DECIMALS)),
            attestations
        );
        // The base column is the orchestrator's view of the call, not this
        // test's.
        grid[0][0] = bytes32(uint256(uint160(MINTER)));
        grid[0][1] = bytes32(uint256(uint160(address(orchestrator))));

        _mockVaultMint(AMOUNT);
        vm.expectEmit(false, false, false, true, address(orchestrator));
        emit IInterpreterCallerV4.ContextV2(MINTER, grid);
        vm.prank(MINTER);
        orchestrator.mint(
            TOKEN, address(recipient), AMOUNT, MintAuthV1({nonce: keccak256("grid"), signature: ""}), "", attestations
        );
    }

    /// The attestations are the minter's input and no part of the
    /// recipient's authorisation: a signature over the EIP-712 digest of
    /// `(token, to, amount, nonce)` authorises the mint whatever attestations
    /// come with it.
    function testAttestationsAreOutsideTheRecipientsAuthorisation() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        vm.startPrank(OWNER);
        orchestrator.setMinterGlobalMintLimit(MINTER, CAPACITY, NO_LEAK);
        orchestrator.setRecipientMintLimit(eoa, CAPACITY, NO_LEAK);
        vm.stopPrank();
        _setWeighting(PRICED);

        bytes32 nonce = keccak256("signed");
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, Digest.unwrap(orchestrator.mintAuthDigest(TOKEN, eoa, AMOUNT, nonce)));
        MintAuthV1 memory auth = MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)});
        SignedContextV1[] memory attestations = _lead(TOKEN_SYMBOL, PRICE);

        _mockVaultMint(AMOUNT);
        vm.prank(MINTER);
        orchestrator.mint(TOKEN, eoa, AMOUNT, auth, "", attestations);
        assertTrue(orchestrator.nonceUsed(eoa, nonce), "the recipient's authorisation was consumed");
        _assertFloatEq(orchestrator.mintHeadroom(MINTER, eoa), _f(1000 - VALUE, 0), "charged the value");
    }

    // ------------------------------------------------------------------ //
    //                        State the expression writes                 //
    // ------------------------------------------------------------------ //

    /// A `set` in the weighting persists to its store under the
    /// orchestrator's namespace, and the next mint's `get` reads it back: a
    /// counter charges 1, then 2.
    function testMintWeightingStateWritesPersist() external {
        _setLimits(CAPACITY, CAPACITY);
        _setWeighting("count: add(get(1) 1), :set(1 count);");
        bytes32 key = Float.unwrap(_f(1, 0));

        _mint(AMOUNT, keccak256("one"), new SignedContextV1[](0));
        _assertFloatEq(_headroom(), _f(999, 0), "the first mint is charged 1");

        _mint(AMOUNT, keccak256("two"), new SignedContextV1[](0));
        _assertFloatEq(_headroom(), _f(997, 0), "the second mint is charged 2");

        _assertFloatEq(
            Float.wrap(I_STORE.get(LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(orchestrator)), key)),
            _f(2, 0),
            "the count lives under the orchestrator's namespace"
        );
        assertEq(
            I_STORE.get(LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this)), key),
            bytes32(0),
            "and nowhere else"
        );
    }
}
