// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {LibLeakyBucket, LeakyBucket} from "rain-lib-leakybucket-0.5.3/src/lib/LibLeakyBucket.sol";
import {SignedContextV2} from "rainlang-0.2.32/src/interface/IInterpreterCallerV5.sol";

import {MintAuthV1, MintLimitV1, MintCapKind} from "src/interface/IST0xOrchestratorV2.sol";
import {ST0xOrchestratorMintWeightingFixture} from "test/src/concrete/ST0xOrchestratorMintWeightingFixture.sol";

/// @title ST0xOrchestratorMintCapStorageTest
/// @notice Storage-layout pin for the mint caps. Each cap lives at
/// `mintCaps[account][kind]` in the ERC-7201 `st0x.orchestrator.main` struct
/// (member 2) as five words: the `LeakyBucket`'s level, timestamp, capacity
/// and leak rate, then the `set` flag. These fail if `rain-lib-leakybucket`
/// adds, reorders or retypes a `LeakyBucket` field, or if `MintCapV1` or
/// `MainStorage` moves a member.
contract ST0xOrchestratorMintCapStorageTest is ST0xOrchestratorMintWeightingFixture {
    using LibDecimalFloat for Float;

    string internal constant TOKEN_SYMBOL = "tAAPL";

    /// @inheritdoc ST0xOrchestratorMintWeightingFixture
    function tokenSymbol() internal pure override returns (string memory) {
        return TOKEN_SYMBOL;
    }

    function _kind(uint256 kindSeed) internal pure returns (MintCapKind) {
        return MintCapKind(bound(kindSeed, 0, uint256(type(MintCapKind).max)));
    }

    function _capBase(MintCapKind kind, address account) internal pure returns (bytes32) {
        bytes32 mainBase =
            keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff));
        bytes32 accountSlot = keccak256(abi.encode(account, uint256(mainBase) + 2));
        return keccak256(abi.encode(uint256(kind), accountSlot));
    }

    function _capWords(MintCapKind kind, address account) internal view returns (bytes32[5] memory) {
        uint256 base = uint256(_capBase(kind, account));
        bytes32[5] memory words;
        for (uint256 i = 0; i < 5; i++) {
            words[i] = vm.load(address(orchestrator), bytes32(base + i));
        }
        return words;
    }

    function _assertCapWordsZero(MintCapKind kind, address account) internal view {
        bytes32[5] memory words = _capWords(kind, account);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(words[i], bytes32(0), string.concat("word ", vm.toString(i)));
        }
    }

    function _now() internal view returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(block.timestamp, 0);
    }

    /// Set `account`'s `kind` cap to `capacity` and `leakRate`, warp
    /// `elapsed`, then mint `amount` with `account` on the `kind` side and
    /// the other side unbounded. Returns the bucket `LibLeakyBucket` computes
    /// for the same steps.
    function _setAndMint(
        MintCapKind kind,
        address account,
        uint256 amount,
        Float capacity,
        Float leakRate,
        uint256 elapsed
    ) internal returns (LeakyBucket memory) {
        address minter = kind == MintCapKind.Minter ? account : MINTER;
        address to = kind == MintCapKind.Recipient ? account : address(recipient);
        if (kind == MintCapKind.Recipient) vm.etch(account, address(recipient).code);

        _setWeighting("_: mint-amount();");
        bytes32 mintRole = orchestrator.MINT_ROLE();
        vm.startPrank(OWNER);
        orchestrator.grantRole(mintRole, minter);
        orchestrator.setMintLimit(kind, account, capacity, leakRate);
        if (kind == MintCapKind.Minter) {
            orchestrator.setMintLimit(MintCapKind.Recipient, to, UNBOUNDED_CAPACITY, NO_LEAK);
        } else {
            orchestrator.setMintLimit(MintCapKind.Minter, minter, UNBOUNDED_CAPACITY, NO_LEAK);
        }
        vm.stopPrank();

        LeakyBucket memory expected;
        expected = LibLeakyBucket.setPolicy(expected, _now(), capacity, leakRate);

        vm.warp(block.timestamp + elapsed);
        _mockVaultMint(amount);
        vm.prank(minter);
        orchestrator.mint(
            TOKEN, to, amount, MintAuthV1({nonce: keccak256("pin"), signature: ""}), "", new SignedContextV2[](0)
        );
        (expected.level, expected.timestamp) = LibLeakyBucket.fill(
            expected, _now(), LibDecimalFloat.fromFixedDecimalLosslessPacked(amount, TOKEN_DECIMALS)
        );
        return expected;
    }

    /// After `setMintLimit` and a weighted mint, the cap's five words are the
    /// bucket `LibLeakyBucket` computes, the policy `mintLimit` reports and a
    /// set flag of one.
    function testFuzzMintCapStorageLayout(
        uint256 kindSeed,
        address account,
        uint256 amount,
        uint256 spareCapacity,
        uint256 leakRateUnits,
        uint256 elapsed
    ) external {
        MintCapKind kind = _kind(kindSeed);
        assumeNotPrecompile(account);
        assumeNotForgeAddress(account);
        vm.assume(account.code.length == 0);
        vm.assume(account != MINTER);
        amount = bound(amount, 1, 1e40);
        Float capacity = LibDecimalFloat.packLossless(int256(amount + bound(spareCapacity, 0, 1e40)), -18);
        Float leakRate = LibDecimalFloat.packLossless(int256(bound(leakRateUnits, 0, 1e40)), -18);

        LeakyBucket memory expected = _setAndMint(kind, account, amount, capacity, leakRate, bound(elapsed, 0, 1e9));
        bytes32[5] memory words = _capWords(kind, account);
        MintLimitV1 memory limit = orchestrator.mintLimit(kind, account);

        assertEq(words[0], Float.unwrap(expected.level), "level is the library's fill");
        _assertFloatEq(
            Float.wrap(words[0]),
            LibDecimalFloat.fromFixedDecimalLosslessPacked(amount, TOKEN_DECIMALS),
            "level is the charge"
        );
        _assertFloatEq(Float.wrap(words[0]), orchestrator.mintLevel(kind, account), "level is mintLevel");

        assertEq(words[1], Float.unwrap(expected.timestamp), "timestamp is the library's fill");
        assertEq(words[1], Float.unwrap(_now()), "timestamp is the mint's");

        assertEq(words[2], Float.unwrap(expected.capacity), "capacity is the library's policy");
        assertEq(words[2], Float.unwrap(limit.capacity), "capacity is mintLimit's");
        assertEq(words[2], Float.unwrap(capacity), "capacity is as set");

        assertEq(words[3], Float.unwrap(expected.leakRate), "leakRate is the library's policy");
        assertEq(words[3], Float.unwrap(limit.leakRate), "leakRate is mintLimit's");
        assertEq(words[3], Float.unwrap(leakRate), "leakRate is as set");

        assertTrue(limit.set, "mintLimit reports set");
        assertEq(words[4], bytes32(uint256(1)), "set flag");
    }

    /// A cap never set is five zero words.
    function testFuzzUnsetMintCapStorageIsZero(uint256 kindSeed, address account) external view {
        MintCapKind kind = _kind(kindSeed);
        _assertCapWordsZero(kind, account);
        MintLimitV1 memory limit = orchestrator.mintLimit(kind, account);
        assertFalse(limit.set, "mintLimit reports unset");
    }

    /// One account's minter and recipient caps sit at distinct bases: each
    /// holds only its own policy.
    function testFuzzMinterAndRecipientCapsOfOneAccountAreDistinct(
        address account,
        uint256 minterCapacityUnits,
        uint256 minterLeakUnits,
        uint256 recipientCapacityUnits,
        uint256 recipientLeakUnits
    ) external {
        Float minterCapacity = LibDecimalFloat.packLossless(int256(bound(minterCapacityUnits, 0, 1e40)), -18);
        Float minterLeak = LibDecimalFloat.packLossless(int256(bound(minterLeakUnits, 0, 1e40)), -18);
        Float recipientCapacity = LibDecimalFloat.packLossless(int256(bound(recipientCapacityUnits, 0, 1e40)), -18);
        Float recipientLeak = LibDecimalFloat.packLossless(int256(bound(recipientLeakUnits, 0, 1e40)), -18);

        assertNotEq(_capBase(MintCapKind.Minter, account), _capBase(MintCapKind.Recipient, account), "bases");

        vm.prank(OWNER);
        orchestrator.setMintLimit(MintCapKind.Minter, account, minterCapacity, minterLeak);
        _assertCapWordsZero(MintCapKind.Recipient, account);

        vm.prank(OWNER);
        orchestrator.setMintLimit(MintCapKind.Recipient, account, recipientCapacity, recipientLeak);

        bytes32[5] memory minterWords = _capWords(MintCapKind.Minter, account);
        bytes32[5] memory recipientWords = _capWords(MintCapKind.Recipient, account);
        assertEq(minterWords[2], Float.unwrap(minterCapacity), "minter capacity");
        assertEq(minterWords[3], Float.unwrap(minterLeak), "minter leakRate");
        assertEq(minterWords[4], bytes32(uint256(1)), "minter set flag");
        assertEq(recipientWords[2], Float.unwrap(recipientCapacity), "recipient capacity");
        assertEq(recipientWords[3], Float.unwrap(recipientLeak), "recipient leakRate");
        assertEq(recipientWords[4], bytes32(uint256(1)), "recipient set flag");
    }
}
