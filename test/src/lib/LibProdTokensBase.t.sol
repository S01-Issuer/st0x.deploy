// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdTokensBase} from "../../../src/lib/LibProdTokensBase.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IReceiptVaultV3} from "rain.vats/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain.vats/interface/IReceiptV3.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain.vats/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";
import {ICertifiableV1} from "rain.vats/interface/ICertifiableV1.sol";
import {
    ERC1967_BEACON_SLOT,
    LibExtrospectERC1967BeaconProxy
} from "rain.extrospection/lib/LibExtrospectERC1967BeaconProxy.sol";
import {LibExtrospectBytecode} from "rain.extrospection/lib/LibExtrospectBytecode.sol";
import {LibExtrospectMetamorphic} from "rain.extrospection/lib/LibExtrospectMetamorphic.sol";
import {EVM_OP_DELEGATECALL} from "rain.extrospection/lib/EVMOpcodes.sol";
import {IExtrospectV1} from "rain.extrospection/interface/IExtrospectV1.sol";
import {EXTROSPECT_ZOLTU_ADDRESS_V1} from "rain.extrospection/concrete/Extrospect.sol";

/// @title LibProdTokensBaseTest
/// @notice Fork tests verifying production token instances on Base.
contract LibProdTokensBaseTest is Test {
    /// Read the EIP-1967 beacon address from a proxy contract.
    function beaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// Verify a token set (receipt, receipt vault, wrapped vault) is deployed,
    /// wired correctly, and behind the expected beacons on the current fork.
    function checkTokenSet(
        address receipt,
        address receiptVault,
        address wrappedTokenVault,
        string memory expectedReceiptVaultSymbol,
        string memory expectedWrappedVaultSymbol
    ) internal view {
        assertTrue(receipt.code.length > 0, "receipt not deployed");
        assertTrue(receiptVault.code.length > 0, "receipt vault not deployed");
        assertTrue(wrappedTokenVault.code.length > 0, "wrapped vault not deployed");

        assertEq(IERC20Metadata(receiptVault).symbol(), expectedReceiptVaultSymbol);
        assertEq(IERC20Metadata(wrappedTokenVault).symbol(), expectedWrappedVaultSymbol);
        assertEq(IERC4626(wrappedTokenVault).asset(), receiptVault, "wrapped vault asset mismatch");
        assertEq(address(IReceiptVaultV3(payable(receiptVault)).receipt()), receipt, "receipt address mismatch");
        // The receipt's manager controls mint/burn. If a prod receipt's
        // manager isn't its receipt vault, the vault can't mint receipts
        // when users deposit nor burn receipts when users withdraw —
        // every deposit and withdraw on this token would revert.
        assertEq(IReceiptV3(receipt).manager(), receiptVault, "receipt manager != receipt vault");

        // All prod tokens on Base are behind the V1 OARV deployer's
        // beacons. The constants are the canonical source — the cross-check
        // that they match runtime resolution lives in
        // `testProdBeaconAddressesMatchConstants`.
        address receiptBeacon = LibProdDeployV1.STOX_RECEIPT_BEACON_V1;
        address receiptVaultBeacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address wrappedVaultBeacon = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1;

        assertEq(beaconOf(receipt), receiptBeacon, "receipt beacon mismatch");
        assertEq(beaconOf(receiptVault), receiptVaultBeacon, "receipt vault beacon mismatch");
        assertEq(beaconOf(wrappedTokenVault), wrappedVaultBeacon, "wrapped vault beacon mismatch");

        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                receiptBeacon, LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            "receipt beacon impl codehash mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                receiptVaultBeacon, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            "receipt vault beacon impl codehash mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                wrappedVaultBeacon, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            "wrapped vault beacon impl codehash mismatch"
        );

        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(receiptBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            "receipt beacon owner mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(receiptVaultBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            "receipt vault beacon owner mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(wrappedVaultBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            "wrapped vault beacon owner mismatch"
        );

        // Receipt vault transfers are gated on `certifiedUntil`. An expired
        // certification freezes all transfers on the affected token. Pin
        // that every prod vault is currently within its certification
        // window at the fork's block timestamp.
        assertFalse(ICertifiableV1(receiptVault).isCertificationExpired(), "receipt vault certification expired");

        // Integrators (DEXes, indexers, UIs) read `decimals()` to scale
        // amounts. Drift from 18 silently shifts every off-chain
        // calculation by ten orders of magnitude per missing decimal.
        assertEq(IERC20Metadata(receiptVault).decimals(), 18, "receipt vault decimals != 18");
        assertEq(IERC20Metadata(wrappedTokenVault).decimals(), 18, "wrapped vault decimals != 18");

        // Per-class proxy codehash consistency. All receipt proxies are
        // BeaconProxy instances pointing at the same beacon, so their
        // runtime bytecode must be identical. Same for receipt vault
        // proxies and wrapped vault proxies. A divergent codehash means
        // a proxy was deployed through a different mechanism or with
        // different constructor args than its siblings. The pinned
        // values live in `LibProdDeployV1` so MSTR is no longer the
        // canonical reference — every prod proxy is checked against an
        // in-repo constant.
        assertEq(
            keccak256(receipt.code),
            LibProdDeployV1.PROD_STOX_RECEIPT_PROXY_BASE_CODEHASH_V1,
            "receipt proxy codehash mismatch"
        );
        assertEq(
            keccak256(receiptVault.code),
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_PROXY_BASE_CODEHASH_V1,
            "receipt vault proxy codehash mismatch"
        );
        assertEq(
            keccak256(wrappedTokenVault.code),
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_PROXY_BASE_CODEHASH_V1,
            "wrapped vault proxy codehash mismatch"
        );

        // Wrapped vault claims (totalAssets) cannot exceed total receipt
        // vault shares minted (totalSupply). The wrapped vault's holdings
        // of the receipt vault are a subset of all minted receipt-vault
        // shares — others may hold receipt-vault shares directly.
        // Violation indicates an accounting bug.
        assertLe(
            IERC4626(wrappedTokenVault).totalAssets(),
            IERC20Metadata(receiptVault).totalSupply(),
            "wrapped vault totalAssets > receipt vault totalSupply"
        );
    }

    /// Pin the prod V1 implementations to be free of Solidity CBOR metadata.
    /// `foundry.toml` sets `bytecode_hash = "none"` and `cbor_metadata =
    /// false` for reproducible Zoltu deployment — this verifies the
    /// deployed bytecode actually reflects those settings rather than
    /// having been smuggled in from a different toolchain config.
    ///
    /// Largely redundant with the codehash pin: if metadata changes, the
    /// codehash changes, and the existing `isBeaconImplementationBytecode`
    /// check catches it. Filed for completeness — the explicit CBOR check
    /// gives a clearer error message ("metadata present" vs "codehash
    /// mismatch") if a future toolchain misconfigures the build.
    function testProdReceiptImplementationHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION);
    }

    function testProdReceiptVaultImplementationHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION);
    }

    function testProdWrappedTokenVaultImplementationHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION);
    }

    function testProdOffchainAssetReceiptVaultBeaconSetDeployerHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
    }

    function testProdWrappedTokenVaultBeaconSetDeployerHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER);
    }

    function testProdUnifiedDeployerHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_UNIFIED_DEPLOYER);
    }

    /// Mutation pin: the no-CBOR tests above all return clean (no revert),
    /// which by itself doesn't prove `checkNoSolidityCBORMetadata` would
    /// catch a deployment that actually carried CBOR metadata. Construct
    /// fake bytecode at a sentinel address using `vm.etch`, with the exact
    /// 53-byte Solidity CBOR trailer (`a2 64 "ipfs" 5822 <34 bytes> 64
    /// "solc" 43 <3 bytes> 0033`), and assert the library reverts with
    /// `UnexpectedMetadata`. Without this, a regression in
    /// `tryTrimSolidityCBORMetadata` (e.g. always returning false) would
    /// silently turn the prod pins into vacuous always-pass tests.
    ///
    /// Routes through the deployed `Extrospect` contract at the
    /// deterministic Zoltu address — `checkNoSolidityCBORMetadata` is
    /// library-internal and inlines into the test contract, so a
    /// same-depth revert wouldn't satisfy `vm.expectRevert`. The
    /// concrete contract provides the external call hop and is on Base
    /// at `EXTROSPECT_ZOLTU_ADDRESS_V1`.
    function testCheckNoSolidityCBORMetadataDetectsCBORTrailer() external {
        LibTestProd.createSelectForkBase(vm);
        bytes memory bytecode = abi.encodePacked(
            hex"00", // STOP — minimal real bytecode prefix
            hex"a2", // cbor map header (2 entries)
            hex"64", // text-string prefix (4 bytes follow)
            hex"69706673", // "ipfs"
            hex"5822", // byte-string prefix (34 bytes follow)
            hex"00000000000000000000000000000000000000000000000000000000000000000000", // 34-byte ipfs hash placeholder
            hex"64", // text-string prefix (4 bytes follow)
            hex"736f6c63", // "solc"
            hex"43", // byte-string prefix (3 bytes follow)
            hex"000804", // solc version placeholder (e.g. 0.8.4)
            hex"0033" // metadata length suffix: 51 bytes
        );

        address sentinel = address(0xCB07);
        vm.etch(sentinel, bytecode);

        vm.expectRevert(bytes4(keccak256("UnexpectedMetadata()")));
        IExtrospectV1(EXTROSPECT_ZOLTU_ADDRESS_V1).checkNoSolidityCBORMetadata(sentinel);
    }

    /// Pin the metamorphic-risk surface of the prod V1 implementations.
    /// `LibExtrospectMetamorphic.scanMetamorphicRisk` returns a bitmap of
    /// reachable opcodes from the metamorphic set (SELFDESTRUCT,
    /// DELEGATECALL, CALLCODE, CREATE, CREATE2 — bits 0xFF, 0xF4, 0xF2,
    /// 0xF0, 0xF5 in the all-opcodes bitmap). The codehash pin in
    /// `checkTokenSet` answers "what bytecode is at this address now";
    /// this test answers "what redeployment surface does that bytecode
    /// expose".
    ///
    /// Empirically, all three V1 implementations have only DELEGATECALL
    /// reachable (bit 244 = `1 << 244`). DELEGATECALL is expected because
    /// the implementations are OZ Upgradeable beacon-proxy targets and
    /// the upgrade / call machinery embedded in the implementation
    /// contains delegatecall sites. The pin captures the currently-known
    /// shape — any change (a new metamorphic op appearing, or
    /// DELEGATECALL going away) trips the test and forces an explicit
    /// re-evaluation.
    ///
    /// Linear bytecode scan is gas-intensive — `rain.extrospection`
    /// algorithms are intended for offchain / fork-test use, which this
    /// test is.
    /// Bitmap pin for `STOX_RECEIPT_VAULT_IMPLEMENTATION`: only DELEGATECALL
    /// is reachable. The receipt vault implementation contains delegatecall
    /// sites from the OZ Upgradeable inheritance chain (and/or ERC2771
    /// forwarder machinery). Receipt and wrapped-vault implementations are
    /// clean (0 — no metamorphic ops reachable). Any drift in either
    /// direction trips the corresponding assertion. Bit position derived
    /// from the upstream `EVM_OP_DELEGATECALL` constant rather than a
    /// literal so the bitmap stays correct if rain.extrospection ever
    /// re-derives opcode numbering.
    uint256 constant METAMORPHIC_RISK_DELEGATECALL_ONLY = 1 << EVM_OP_DELEGATECALL;

    function testProdReceiptImplementationMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION.code),
            0,
            "STOX_RECEIPT_IMPLEMENTATION metamorphic surface drifted"
        );
    }

    function testProdReceiptVaultImplementationMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION.code),
            METAMORPHIC_RISK_DELEGATECALL_ONLY,
            "STOX_RECEIPT_VAULT_IMPLEMENTATION metamorphic surface drifted"
        );
    }

    function testProdWrappedTokenVaultImplementationMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION.code),
            0,
            "STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION metamorphic surface drifted"
        );
    }

    /// Single pin test: the runtime-resolved V1 beacon addresses match
    /// the in-repo constants. Once this passes, the rest of the prod
    /// fork tests can use the `STOX_*_BEACON_V1` constants directly
    /// without re-resolving from the deployer's getters or the proxy
    /// slot — the constants are the canonical source, runtime resolution
    /// is the cross-check.
    function testProdBeaconAddressesMatchConstants() external {
        LibTestProd.createSelectForkBase(vm);
        IOffchainAssetReceiptVaultBeaconSetDeployerV1 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV1(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
        assertEq(
            address(oarvDeployer.I_RECEIPT_BEACON()),
            LibProdDeployV1.STOX_RECEIPT_BEACON_V1,
            "I_RECEIPT_BEACON resolved to unexpected address"
        );
        assertEq(
            address(oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON()),
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1,
            "I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON resolved to unexpected address"
        );
        // All wrapped vault proxies share a single beacon. Read it from
        // any wrapped proxy (MSTR is arbitrary) and assert the constant.
        assertEq(
            beaconOf(LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT),
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1,
            "wrapped vault beacon read from MSTR proxy slot drifted"
        );
    }

    function testMstrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.MSTR_RECEIPT,
            LibProdTokensBase.MSTR_RECEIPT_VAULT,
            LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT,
            "tMSTR",
            "wtMSTR"
        );
    }

    function testTslaTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.TSLA_RECEIPT,
            LibProdTokensBase.TSLA_RECEIPT_VAULT,
            LibProdTokensBase.TSLA_WRAPPED_TOKEN_VAULT,
            "tTSLA",
            "wtTSLA"
        );
    }

    function testCoinTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.COIN_RECEIPT,
            LibProdTokensBase.COIN_RECEIPT_VAULT,
            LibProdTokensBase.COIN_WRAPPED_TOKEN_VAULT,
            "tCOIN",
            "wtCOIN"
        );
    }

    function testSpymTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.SPYM_RECEIPT,
            LibProdTokensBase.SPYM_RECEIPT_VAULT,
            LibProdTokensBase.SPYM_WRAPPED_TOKEN_VAULT,
            "tSPYM",
            "wtSPYM"
        );
    }

    function testSivrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.SIVR_RECEIPT,
            LibProdTokensBase.SIVR_RECEIPT_VAULT,
            LibProdTokensBase.SIVR_WRAPPED_TOKEN_VAULT,
            "tSIVR",
            "wtSIVR"
        );
    }

    function testCrclTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.CRCL_RECEIPT,
            LibProdTokensBase.CRCL_RECEIPT_VAULT,
            LibProdTokensBase.CRCL_WRAPPED_TOKEN_VAULT,
            "tCRCL",
            "wtCRCL"
        );
    }

    function testNvdaTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.NVDA_RECEIPT,
            LibProdTokensBase.NVDA_RECEIPT_VAULT,
            LibProdTokensBase.NVDA_WRAPPED_TOKEN_VAULT,
            "tNVDA",
            "wtNVDA"
        );
    }

    function testIauTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.IAU_RECEIPT,
            LibProdTokensBase.IAU_RECEIPT_VAULT,
            LibProdTokensBase.IAU_WRAPPED_TOKEN_VAULT,
            "tIAU",
            "wtIAU"
        );
    }

    function testPpltTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.PPLT_RECEIPT,
            LibProdTokensBase.PPLT_RECEIPT_VAULT,
            LibProdTokensBase.PPLT_WRAPPED_TOKEN_VAULT,
            "tPPLT",
            "wtPPLT"
        );
    }

    function testAmznTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.AMZN_RECEIPT,
            LibProdTokensBase.AMZN_RECEIPT_VAULT,
            LibProdTokensBase.AMZN_WRAPPED_TOKEN_VAULT,
            "tAMZN",
            "wtAMZN"
        );
    }

    function testBmnrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.BMNR_RECEIPT,
            LibProdTokensBase.BMNR_RECEIPT_VAULT,
            LibProdTokensBase.BMNR_WRAPPED_TOKEN_VAULT,
            "tBMNR",
            "wtBMNR"
        );
    }

    function testIbhgTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.IBHG_RECEIPT,
            LibProdTokensBase.IBHG_RECEIPT_VAULT,
            LibProdTokensBase.IBHG_WRAPPED_TOKEN_VAULT,
            "tIBHG",
            "wtIBHG"
        );
    }

    function testSgovTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.SGOV_RECEIPT,
            LibProdTokensBase.SGOV_RECEIPT_VAULT,
            LibProdTokensBase.SGOV_WRAPPED_TOKEN_VAULT,
            "tSGOV",
            "wtSGOV"
        );
    }
}
