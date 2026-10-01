// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.6.1/interfaces/IERC4626.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.1/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.1/src/interface/IReceiptV3.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain-vats-0.2.1/src/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";
import {ICertifiableV1} from "rain-vats-0.2.1/src/interface/ICertifiableV1.sol";
import {
    ERC1967_BEACON_SLOT,
    LibExtrospectERC1967BeaconProxy
} from "rain-extrospection-0.1.14/src/lib/LibExtrospectERC1967BeaconProxy.sol";
import {LibExtrospectBytecode} from "rain-extrospection-0.1.14/src/lib/LibExtrospectBytecode.sol";
import {LibExtrospectMetamorphic} from "rain-extrospection-0.1.14/src/lib/LibExtrospectMetamorphic.sol";
import {EVM_OP_CREATE, EVM_OP_DELEGATECALL} from "rain-extrospection-0.1.14/src/lib/EVMOpcodes.sol";
import {IExtrospectV1} from "rain-extrospection-0.1.14/src/interface/IExtrospectV1.sol";
import {IBeacon} from "rain-extrospection-0.1.14/src/interface/IBeacon.sol";

/// @dev The deterministic Zoltu address of the deployed `Extrospect`
/// concrete, the `IExtrospectV1` this test calls on Base.
address constant EXTROSPECT_ZOLTU_ADDRESS_V1 = address(0x1BE878af679C1a0A6AC15108b0F4398de1f94506);

/// @title LibTokenInvariantsAddressesTest
/// @notice Fork tests verifying production token instances on Base.
contract LibTokenInvariantsAddressesTest is Test {
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
        // The receipt's manager controls mint/burn and must be its vault.
        assertEq(IReceiptV3(receipt).manager(), receiptVault, "receipt manager != receipt vault");

        // All prod tokens on Base are behind the V1 OARV deployer's
        // beacons; `testProdBeaconAddressesMatchConstants` cross-checks the
        // constants against runtime resolution.
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

        // Every prod vault is within its certification window at the fork's
        // block timestamp; an expired certification freezes transfers.
        assertFalse(ICertifiableV1(receiptVault).isCertificationExpired(), "receipt vault certification expired");

        assertEq(IERC20Metadata(receiptVault).decimals(), 18, "receipt vault decimals != 18");
        assertEq(IERC20Metadata(wrappedTokenVault).decimals(), 18, "wrapped vault decimals != 18");

        // Per-class proxy codehash. All proxies of one class are
        // BeaconProxy instances pointing at the same beacon, so their
        // runtime bytecode is identical; a divergent codehash means a
        // proxy was deployed through a different mechanism or with
        // different constructor args than its siblings.
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

        // The wrapped vault's `totalAssets` is a subset of the receipt
        // vault's minted shares, so it cannot exceed `totalSupply`.
        assertLe(
            IERC4626(wrappedTokenVault).totalAssets(),
            IERC20Metadata(receiptVault).totalSupply(),
            "wrapped vault totalAssets > receipt vault totalSupply"
        );
    }

    /// Pin the prod V1 implementations to be free of Solidity CBOR metadata,
    /// as `foundry.toml`'s `bytecode_hash = "none"` and `cbor_metadata =
    /// false` produce.
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

    function testProdReceiptBeaconHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_RECEIPT_BEACON_V1);
    }

    function testProdReceiptVaultBeaconHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1);
    }

    function testProdWrappedTokenVaultBeaconHasNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        LibExtrospectBytecode.checkNoSolidityCBORMetadata(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1);
    }

    /// All three V1 beacons are `UpgradeableBeacon` instances with identical
    /// runtime bytecode; pin the shared codehash.
    function testProdReceiptBeaconRuntimeCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(LibProdDeployV1.STOX_RECEIPT_BEACON_V1.codehash, LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1);
    }

    function testProdReceiptVaultBeaconRuntimeCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1.codehash, LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1
        );
    }

    function testProdWrappedTokenVaultBeaconRuntimeCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1.codehash,
            LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1
        );
    }

    /// `checkNoSolidityCBORMetadata` reverts with `UnexpectedMetadata` on
    /// bytecode carrying the 53-byte Solidity CBOR trailer (`a2 64 "ipfs"
    /// 5822 <34 bytes> 64 "solc" 43 <3 bytes> 0033`), etched at a sentinel
    /// address. Routes through the deployed `Extrospect` contract at
    /// `EXTROSPECT_ZOLTU_ADDRESS_V1` because the library function inlines
    /// into the test contract and a same-depth revert does not satisfy
    /// `vm.expectRevert`.
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

    /// `LibExtrospectMetamorphic.scanMetamorphicRisk` bitmap pin for
    /// `STOX_RECEIPT_VAULT_IMPLEMENTATION`: only DELEGATECALL is reachable.
    /// The receipt and wrapped-vault implementations scan to 0.
    uint256 constant METAMORPHIC_RISK_DELEGATECALL_ONLY = uint256(1) << uint256(EVM_OP_DELEGATECALL);

    /// Bitmap pin for the OARV and wrapped vault beacon-set deployers:
    /// `CREATE` (the deployer constructs beacons) and `DELEGATECALL` are
    /// reachable.
    uint256 constant METAMORPHIC_RISK_CREATE_AND_DELEGATECALL =
        (uint256(1) << uint256(EVM_OP_CREATE)) | (uint256(1) << uint256(EVM_OP_DELEGATECALL));

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

    /// Metamorphic-risk bitmap pins for the three first-party deployers.
    function testProdOffchainAssetReceiptVaultBeaconSetDeployerMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(
                LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.code
            ),
            METAMORPHIC_RISK_CREATE_AND_DELEGATECALL,
            "OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER metamorphic surface drifted"
        );
    }

    function testProdWrappedTokenVaultBeaconSetDeployerMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(
                LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.code
            ),
            METAMORPHIC_RISK_CREATE_AND_DELEGATECALL,
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER metamorphic surface drifted"
        );
    }

    function testProdUnifiedDeployerMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_UNIFIED_DEPLOYER.code),
            0,
            "STOX_UNIFIED_DEPLOYER metamorphic surface drifted"
        );
    }

    /// Metamorphic-risk bitmap pins for the three V1 beacons: 0 each.
    function testProdReceiptBeaconMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_RECEIPT_BEACON_V1.code),
            0,
            "STOX_RECEIPT_BEACON_V1 metamorphic surface drifted"
        );
    }

    function testProdReceiptVaultBeaconMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1.code),
            0,
            "STOX_RECEIPT_VAULT_BEACON_V1 metamorphic surface drifted"
        );
    }

    function testProdWrappedTokenVaultBeaconMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            LibExtrospectMetamorphic.scanMetamorphicRisk(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1.code),
            0,
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_V1 metamorphic surface drifted"
        );
    }

    /// Pin the deployed runtime bytecode of each prod V1 deployer against
    /// its `LibProdDeployV1.PROD_*_BASE_CODEHASH_V1` constant.
    function testProdOffchainAssetReceiptVaultBeaconSetDeployerCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            keccak256(LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.code),
            LibProdDeployV1.PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1,
            "OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER codehash drifted"
        );
    }

    function testProdWrappedTokenVaultBeaconSetDeployerCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            keccak256(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.code),
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1,
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER codehash drifted"
        );
    }

    function testProdUnifiedDeployerCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            keccak256(LibProdDeployV1.STOX_UNIFIED_DEPLOYER.code),
            LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1,
            "STOX_UNIFIED_DEPLOYER codehash drifted"
        );

        // Overwriting the deployer's bytecode makes the codehash check fail.
        vm.etch(LibProdDeployV1.STOX_UNIFIED_DEPLOYER, hex"00");
        assertNotEq(
            keccak256(LibProdDeployV1.STOX_UNIFIED_DEPLOYER.code),
            LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1,
            "swapped bytecode must not match the pinned codehash"
        );
    }

    /// The runtime-resolved V1 beacon addresses match the
    /// `STOX_*_BEACON_V1` constants.
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
            beaconOf(LibTokenInvariants.MSTR_WRAPPED_TOKEN_VAULT),
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1,
            "wrapped vault beacon read from MSTR proxy slot drifted"
        );
    }

    /// Pins the receipt beacon's `implementation()` at
    /// `PROD_TEST_BLOCK_NUMBER_BASE`, a V1-era block: the answer is frozen
    /// with the block, so this is a record of the V1
    /// `STOX_*_IMPLEMENTATION` constants, not a drift detector. The
    /// `*AtBaseHead` counterpart below checks what production serves now.
    function testProdReceiptBeaconImplementationAddressAtPinnedBlock() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            IBeacon(LibProdDeployV1.STOX_RECEIPT_BEACON_V1).implementation(),
            LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION,
            "STOX_RECEIPT_BEACON_V1.implementation() drifted"
        );
    }

    /// Pins the receipt-vault beacon's `implementation()` at
    /// `PROD_TEST_BLOCK_NUMBER_BASE`, on the same terms as above.
    function testProdReceiptVaultBeaconImplementationAddressAtPinnedBlock() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            IBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(),
            LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
            "STOX_RECEIPT_VAULT_BEACON_V1.implementation() drifted"
        );
    }

    /// Pins the wrapped-vault beacon's `implementation()` at
    /// `PROD_TEST_BLOCK_NUMBER_BASE`, on the same terms as above.
    function testProdWrappedTokenVaultBeaconImplementationAddressAtPinnedBlock() external {
        LibTestProd.createSelectForkBase(vm);
        assertEq(
            IBeacon(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1).implementation(),
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_V1.implementation() drifted"
        );
    }

    /// At Base HEAD the receipt beacon serves the 0.1.30 receipt. Every
    /// other beacon-impl assertion in this file is pinned to a V1-era block.
    function testProdReceiptBeaconImplementationAddressAtBaseHead() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEq(
            IBeacon(LibProdDeployV1.STOX_RECEIPT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_RECEIPT_0_1_30,
            "live STOX_RECEIPT_BEACON_V1.implementation() is not the 0.1.30 receipt"
        );
    }

    /// At Base HEAD the receipt-vault beacon serves the 0.1.30 vault.
    function testProdReceiptVaultBeaconImplementationAddressAtBaseHead() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEq(
            IBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
            "live STOX_RECEIPT_VAULT_BEACON_V1.implementation() is not the 0.1.30 receipt vault"
        );
    }

    /// At Base HEAD the wrapped-vault beacon serves the 0.1.1 implementation.
    function testProdWrappedTokenVaultBeaconImplementationAddressAtBaseHead() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEq(
            IBeacon(LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1).implementation(),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1,
            "live STOX_WRAPPED_TOKEN_VAULT_BEACON_V1.implementation() is not the 0.1.1 wrapped token vault"
        );
    }

    function testMstrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.MSTR_RECEIPT,
            LibTokenInvariants.MSTR_RECEIPT_VAULT,
            LibTokenInvariants.MSTR_WRAPPED_TOKEN_VAULT,
            "tMSTR",
            "wtMSTR"
        );
    }

    function testTslaTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.TSLA_RECEIPT,
            LibTokenInvariants.TSLA_RECEIPT_VAULT,
            LibTokenInvariants.TSLA_WRAPPED_TOKEN_VAULT,
            "tTSLA",
            "wtTSLA"
        );
    }

    function testCoinTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.COIN_RECEIPT,
            LibTokenInvariants.COIN_RECEIPT_VAULT,
            LibTokenInvariants.COIN_WRAPPED_TOKEN_VAULT,
            "tCOIN",
            "wtCOIN"
        );
    }

    function testSpymTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.SPYM_RECEIPT,
            LibTokenInvariants.SPYM_RECEIPT_VAULT,
            LibTokenInvariants.SPYM_WRAPPED_TOKEN_VAULT,
            "tSPYM",
            "wtSPYM"
        );
    }

    function testSivrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.SIVR_RECEIPT,
            LibTokenInvariants.SIVR_RECEIPT_VAULT,
            LibTokenInvariants.SIVR_WRAPPED_TOKEN_VAULT,
            "tSIVR",
            "wtSIVR"
        );
    }

    function testCrclTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.CRCL_RECEIPT,
            LibTokenInvariants.CRCL_RECEIPT_VAULT,
            LibTokenInvariants.CRCL_WRAPPED_TOKEN_VAULT,
            "tCRCL",
            "wtCRCL"
        );
    }

    function testNvdaTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.NVDA_RECEIPT,
            LibTokenInvariants.NVDA_RECEIPT_VAULT,
            LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT,
            "tNVDA",
            "wtNVDA"
        );
    }

    function testIauTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.IAU_RECEIPT,
            LibTokenInvariants.IAU_RECEIPT_VAULT,
            LibTokenInvariants.IAU_WRAPPED_TOKEN_VAULT,
            "tIAU",
            "wtIAU"
        );
    }

    function testPpltTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.PPLT_RECEIPT,
            LibTokenInvariants.PPLT_RECEIPT_VAULT,
            LibTokenInvariants.PPLT_WRAPPED_TOKEN_VAULT,
            "tPPLT",
            "wtPPLT"
        );
    }

    function testAmznTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.AMZN_RECEIPT,
            LibTokenInvariants.AMZN_RECEIPT_VAULT,
            LibTokenInvariants.AMZN_WRAPPED_TOKEN_VAULT,
            "tAMZN",
            "wtAMZN"
        );
    }

    function testBmnrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.BMNR_RECEIPT,
            LibTokenInvariants.BMNR_RECEIPT_VAULT,
            LibTokenInvariants.BMNR_WRAPPED_TOKEN_VAULT,
            "tBMNR",
            "wtBMNR"
        );
    }

    function testIbhgTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.IBHG_RECEIPT,
            LibTokenInvariants.IBHG_RECEIPT_VAULT,
            LibTokenInvariants.IBHG_WRAPPED_TOKEN_VAULT,
            "tIBHG",
            "wtIBHG"
        );
    }

    function testSgovTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.SGOV_RECEIPT,
            LibTokenInvariants.SGOV_RECEIPT_VAULT,
            LibTokenInvariants.SGOV_WRAPPED_TOKEN_VAULT,
            "tSGOV",
            "wtSGOV"
        );
    }

    function testQqqmTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.QQQM_RECEIPT,
            LibTokenInvariants.QQQM_RECEIPT_VAULT,
            LibTokenInvariants.QQQM_WRAPPED_TOKEN_VAULT,
            "tQQQM",
            "wtQQQM"
        );
    }

    function testVwoTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.VWO_RECEIPT,
            LibTokenInvariants.VWO_RECEIPT_VAULT,
            LibTokenInvariants.VWO_WRAPPED_TOKEN_VAULT,
            "tVWO",
            "wtVWO"
        );
    }

    function testArkkTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.ARKK_RECEIPT,
            LibTokenInvariants.ARKK_RECEIPT_VAULT,
            LibTokenInvariants.ARKK_WRAPPED_TOKEN_VAULT,
            "tARKK",
            "wtARKK"
        );
    }

    function testSpcxTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.SPCX_RECEIPT,
            LibTokenInvariants.SPCX_RECEIPT_VAULT,
            LibTokenInvariants.SPCX_WRAPPED_TOKEN_VAULT,
            "tSPCX",
            "wtSPCX"
        );
    }

    function testCegTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.CEG_RECEIPT,
            LibTokenInvariants.CEG_RECEIPT_VAULT,
            LibTokenInvariants.CEG_WRAPPED_TOKEN_VAULT,
            "tCEG",
            "wtCEG"
        );
    }

    function testDramTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.DRAM_RECEIPT,
            LibTokenInvariants.DRAM_RECEIPT_VAULT,
            LibTokenInvariants.DRAM_WRAPPED_TOKEN_VAULT,
            "tDRAM",
            "wtDRAM"
        );
    }

    function testTsmTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibTokenInvariants.TSM_RECEIPT,
            LibTokenInvariants.TSM_RECEIPT_VAULT,
            LibTokenInvariants.TSM_WRAPPED_TOKEN_VAULT,
            "tTSM",
            "wtTSM"
        );
    }
}
