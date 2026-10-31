// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {ReceiptVault} from "rain-vats-0.2.13/src/abstract/ReceiptVault.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {EvaluableV4} from "rainlang-0.2.30/src/interface/deprecated/v3/IInterpreterCallerV4.sol";
import {SignedContextV1} from "rainlang-interface-0.2.13/src/interface/IInterpreterCallerV4.sol";

import {ST0xOrchestrator} from "src/concrete/ST0xOrchestrator.sol";
import {LibSafeInvariants} from "src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "src/lib/LibTimelockInvariants.sol";
import {MintAuthV1} from "src/interface/IST0xOrchestratorV2.sol";
import {LibProdDeployV4} from "src/generated/LibProdDeployV4.sol";
import {LibTestRegistryBeaconProxy} from "test/lib/LibTestRegistryBeaconProxy.sol";
import {St0xAttestSubParserTest} from "test/src/concrete/St0xAttestSubParserTest.sol";
import {MockMintRecipient} from "test/src/concrete/MockMintRecipient.sol";

/// @title ST0xOrchestratorMintWeightingFixture
/// @notice A real orchestrator proxy with the vault side mocked, as in
/// `ST0xOrchestrator.t.sol`, for the tests that mint through a Rainlang
/// weighting. The token is mocked with 18 decimals and the symbol
/// `tokenSymbol()` answers, so `mint-amount()` is the amount in WHOLE tokens
/// and a mint of `2e18` units at a lead price of `150` is worth `300`, not
/// `2e18`.
abstract contract ST0xOrchestratorMintWeightingFixture is St0xAttestSubParserTest {
    using LibDecimalFloat for Float;

    /// The mocked vault ("token") and its receipt.
    address internal constant TOKEN = address(0xA11E);
    address internal constant RECEIPT_ADDR = address(0xEEC1);

    /// The one `MINT_ROLE` holder.
    address internal constant MINTER = address(0x111A);
    /// The admin `initialize` seats: the Base governance timelock, since
    /// `setUp` runs on Base's chain id.
    address internal constant OWNER = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;

    /// The beacons the token and its receipt are registry beacon proxies over.
    address internal constant VAULT_BEACON = address(0xBEAC04);
    address internal constant RECEIPT_BEACON = address(0xBEAC12);

    /// What the token answers `decimals()` with.
    uint8 internal constant TOKEN_DECIMALS = 18;

    /// The canonical mint: two whole tokens at a lead price of 150 is a
    /// value of 300.
    uint256 internal constant AMOUNT = 2e18;
    int256 internal constant PRICE = 150;
    int256 internal constant VALUE = 300;

    /// The canonical weighting: the mint's value at the lead's price.
    string internal constant PRICED = "_: mul(mint-amount() lead-price());";

    /// A capacity the value fits and the raw amount does not.
    Float internal immutable CAPACITY = LibDecimalFloat.packLossless(1000, 0);

    /// A capacity nothing here comes near.
    Float internal immutable UNBOUNDED_CAPACITY = LibDecimalFloat.packLossless(1, 60);

    Float internal constant NO_LEAK = LibDecimalFloat.FLOAT_ZERO;

    ST0xOrchestrator internal orchestrator;
    MockMintRecipient internal recipient;

    /// What the token answers `symbol()` with.
    function tokenSymbol() internal pure virtual returns (string memory);

    function setUp() public virtual {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        recipient = new MockMintRecipient(true);
        _makeGuardPass();
        ST0xOrchestrator impl = new ST0xOrchestrator();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        BeaconProxy proxy = new BeaconProxy(address(beacon), abi.encodeCall(ST0xOrchestrator.initialize, ()));
        orchestrator = ST0xOrchestrator(payable(address(proxy)));

        _mockToken(TOKEN, tokenSymbol());

        bytes32 mintRole = orchestrator.MINT_ROLE();
        vm.prank(OWNER);
        orchestrator.grantRole(mintRole, MINTER);
    }

    // ------------------------------------------------------------------ //
    //                              Helpers                               //
    // ------------------------------------------------------------------ //

    /// Etch `token` and its receipt as registry beacon proxies and mock
    /// `token` as a vault whose ERC20 `symbol()` is `symbol_`, with
    /// `TOKEN_DECIMALS` decimals, a receipt, and transfers that succeed.
    function _mockToken(address token, string memory symbol_) internal {
        LibTestRegistryBeaconProxy.etch(vm, token, VAULT_BEACON);
        LibTestRegistryBeaconProxy.etch(vm, RECEIPT_ADDR, RECEIPT_BEACON);
        vm.mockCall(token, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(RECEIPT_ADDR));
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode(symbol_));
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(TOKEN_DECIMALS));
        vm.mockCall(token, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    }

    /// Make the vault-logic version guard pass.
    function _makeGuardPass() internal {
        vm.mockCall(
            VAULT_BEACON,
            abi.encodeWithSelector(IBeacon.implementation.selector),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE)
        );
        vm.mockCall(
            RECEIPT_BEACON,
            abi.encodeWithSelector(IBeacon.implementation.selector),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_CANDIDATE)
        );
    }

    /// `coefficient * 10 ** exponent`.
    function _f(int256 coefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// Numeric `Float` equality: `300` may come back from `mul` in any
    /// spelling, so a charge is compared as a number, never as bytes.
    function _assertFloatEq(Float actual, Float expected, string memory err) internal pure {
        assertTrue(actual.eq(expected), string.concat(err, ": got ", _str(actual), ", want ", _str(expected)));
    }

    function _str(Float float_) internal pure returns (string memory) {
        (int256 coefficient, int256 exponent) = float_.unpack();
        return string.concat(vm.toString(coefficient), "e", vm.toString(exponent));
    }

    /// `rainlang`, with the subparser's pragma prepended, parsed by the test
    /// deployer and bound to the test interpreter and store.
    function _weighting(string memory rainlang) internal view returns (EvaluableV4 memory) {
        return _evaluable(string.concat(usingWords(), rainlang));
    }

    /// `rainlang`, complete with its own pragma, parsed by the test deployer
    /// and bound to the test interpreter and store.
    function _evaluable(string memory rainlang) internal view returns (EvaluableV4 memory) {
        return EvaluableV4({interpreter: I_INTERPRETER, store: I_STORE, bytecode: I_COMPILER.parse2(bytes(rainlang))});
    }

    /// Install `rainlang` as the weighting, as OWNER. Parsed before the
    /// prank, since `parse2` is an external call the prank would land on.
    function _setWeighting(string memory rainlang) internal returns (EvaluableV4 memory) {
        return _install(_weighting(rainlang));
    }

    /// Install `evaluable` as the weighting, as OWNER.
    function _install(EvaluableV4 memory evaluable) internal returns (EvaluableV4 memory) {
        vm.prank(OWNER);
        orchestrator.setMintWeighting(evaluable);
        return evaluable;
    }

    /// Set the minter's and the recipient's limits, as OWNER.
    function _setLimits(Float minterCapacity, Float recipientCapacity) internal {
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER, minterCapacity, NO_LEAK);
        orchestrator.setRecipientMintLimit(address(recipient), recipientCapacity, NO_LEAK);
        vm.stopPrank();
    }

    /// One attestation, the lead's, of `[attestedSymbol, price, now]`.
    function _lead(string memory attestedSymbol, int256 price) internal view returns (SignedContextV1[] memory) {
        SignedContextV1[] memory attestations = new SignedContextV1[](1);
        attestations[0] = attest(LEAD_KEY, symbol(attestedSymbol), float(price), float(int256(block.timestamp)));
        return attestations;
    }

    /// Mock the vault side of a mint of exactly `amount` of `token`.
    function _mockVaultMint(address token, uint256 amount) internal {
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), ""),
            abi.encode(amount)
        );
    }

    /// Mock the vault side of a mint of exactly `amount` of `TOKEN`.
    function _mockVaultMint(uint256 amount) internal {
        _mockVaultMint(TOKEN, amount);
    }

    /// Mint `amount` of `token` to `recipient` from `MINTER`, with
    /// `attestations`. The recipient authorises by callback.
    function _mint(address token, uint256 amount, bytes32 nonce, SignedContextV1[] memory attestations) internal {
        _mockVaultMint(token, amount);
        vm.prank(MINTER);
        orchestrator.mint(
            token, address(recipient), amount, MintAuthV1({nonce: nonce, signature: ""}), "", attestations
        );
    }

    /// Mint `amount` of `TOKEN` to `recipient` from `MINTER`, with
    /// `attestations`. The recipient authorises by callback.
    function _mint(uint256 amount, bytes32 nonce, SignedContextV1[] memory attestations) internal {
        _mint(TOKEN, amount, nonce, attestations);
    }

    /// As `_mint`, expecting a revert, whose data is returned for the tests
    /// that compare a carried `Float` as a number.
    function _mintReverts(address token, uint256 amount, bytes32 nonce, SignedContextV1[] memory attestations)
        internal
        returns (bytes memory)
    {
        _mockVaultMint(token, amount);
        vm.prank(MINTER);
        try orchestrator.mint(
            token, address(recipient), amount, MintAuthV1({nonce: nonce, signature: ""}), "", attestations
        ) {
            revert("the mint was expected to revert");
        } catch (bytes memory reason) {
            return reason;
        }
    }

    /// As `_mintReverts`, of `TOKEN`.
    function _mintReverts(uint256 amount, bytes32 nonce, SignedContextV1[] memory attestations)
        internal
        returns (bytes memory)
    {
        return _mintReverts(TOKEN, amount, nonce, attestations);
    }

    /// The arguments of a `*CapExceeded(address, Float, Float, Float)` error,
    /// after checking its selector.
    function _decodeCapExceeded(bytes memory reason, bytes4 selector)
        internal
        pure
        returns (address who, Float capacity, Float headroom, Float charge)
    {
        // The truncation to the selector is intended.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes32(bytes4(reason)), bytes32(selector), "selector");
        bytes memory args = new bytes(reason.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = reason[i + 4];
        }
        bytes32 capacityWord;
        bytes32 headroomWord;
        bytes32 chargeWord;
        (who, capacityWord, headroomWord, chargeWord) = abi.decode(args, (address, bytes32, bytes32, bytes32));
        return (who, Float.wrap(capacityWord), Float.wrap(headroomWord), Float.wrap(chargeWord));
    }

    function _headroom() internal view returns (Float) {
        return orchestrator.mintHeadroom(MINTER, address(recipient));
    }
}
