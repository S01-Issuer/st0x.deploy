// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.20/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.20/src/interface/IReceiptV3.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain-vats-0.2.20/src/interface/deprecated/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";
import {ICertifiableV1} from "rain-vats-0.2.20/src/interface/ICertifiableV1.sol";
import {
    ERC1967_BEACON_SLOT,
    LibExtrospectERC1967BeaconProxy
} from "rain-extrospection-0.1.16/src/lib/LibExtrospectERC1967BeaconProxy.sol";
import {LibExtrospectBytecode} from "rain-extrospection-0.1.16/src/lib/LibExtrospectBytecode.sol";
import {LibExtrospectMetamorphic} from "rain-extrospection-0.1.16/src/lib/LibExtrospectMetamorphic.sol";
import {EVM_OP_CREATE, EVM_OP_DELEGATECALL} from "rain-extrospection-0.1.16/src/lib/EVMOpcodes.sol";
import {IExtrospectV1} from "rain-extrospection-0.1.16/src/interface/IExtrospectV1.sol";
import {DEPLOYED_ADDRESS as EXTROSPECT_0_1_0} from "rain-extrospection-deploy-0.1.2/src/generated/0_1_0/Extrospect.sol";
import {IBeacon} from "rain-extrospection-0.1.16/src/interface/IBeacon.sol";

/// @notice A pinned wrapped symbol is not of the initialized `wt<TICKER>`
/// form, so no renamed symbol can be derived from it.
/// @param symbol The pinned symbol.
error InvalidInitializedWrappedSymbol(string symbol);

/// @title LibTokenInvariantsAddressesTest
/// @notice Fork tests verifying production token instances on Base.
contract LibTokenInvariantsAddressesTest is Test {
    /// Read the EIP-1967 beacon address from a proxy contract.
    function beaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// The wrapped vault's symbol once the underlying-naming rename has set
    /// the receipt vault's ticker: `"wtMSTR"` becomes `"MSTRs"`.
    /// @param initialWrappedSymbol The initialized `"wt" + ticker` symbol.
    /// @return renamed `ticker + "s"`.
    function renamedWrappedSymbol(string memory initialWrappedSymbol) internal pure returns (string memory renamed) {
        bytes memory initial = bytes(initialWrappedSymbol);
        if (initial.length <= 2 || initial[0] != "w" || initial[1] != "t") {
            revert InvalidInitializedWrappedSymbol(initialWrappedSymbol);
        }
        bytes memory ticker = new bytes(initial.length - 2);
        for (uint256 i = 0; i < ticker.length; i++) {
            ticker[i] = initial[i + 2];
        }
        renamed = string.concat(string(ticker), "s");
    }

    function externalRenamedWrappedSymbol(string memory initial) external pure returns (string memory) {
        return renamedWrappedSymbol(initial);
    }

    /// The renamed wrapper symbol drops the `wt` prefix and appends `s`.
    function testRenamedWrappedSymbolDerivation() external pure {
        assertEq(renamedWrappedSymbol("wtMSTR"), "MSTRs");
        assertEq(renamedWrappedSymbol("wtBRK.B"), "BRK.Bs");
        assertEq(renamedWrappedSymbol("wtA"), "As");
    }

    /// A pinned symbol that is not `wt` + a non-empty ticker refuses.
    function testRenamedWrappedSymbolRefusesInvalidInitialSymbols() external {
        string[5] memory invalid = [string(""), "w", "wt", "xtNVDA", "wxNVDA"];
        for (uint256 index = 0; index < invalid.length; index++) {
            vm.expectRevert(abi.encodeWithSelector(InvalidInitializedWrappedSymbol.selector, invalid[index]));
            this.externalRenamedWrappedSymbol(invalid[index]);
        }
    }

    /// `message` prefixed with the token set's ticker.
    function named(TokenInstance memory token, string memory message) internal pure returns (string memory) {
        return string.concat(token.underlying, " ", message);
    }

    /// Verify a token set (receipt, receipt vault, wrapped vault) is deployed,
    /// wired correctly, and behind the expected beacons on the current fork.
    /// The receipt vault's symbol is `t<TICKER>`; the wrapped vault's is
    /// accepted as the initialized `wt<TICKER>` or, once the underlying-naming
    /// rename has run, `<TICKER>s`.
    function checkTokenSet(TokenInstance memory token) internal view {
        address receipt = token.receipt;
        address receiptVault = token.receiptVault;
        address wrappedTokenVault = token.wrappedTokenVault;
        assertTrue(receipt.code.length > 0, named(token, "receipt not deployed"));
        assertTrue(receiptVault.code.length > 0, named(token, "receipt vault not deployed"));
        assertTrue(wrappedTokenVault.code.length > 0, named(token, "wrapped vault not deployed"));

        assertEq(
            IERC20Metadata(receiptVault).symbol(),
            string.concat("t", token.underlying),
            named(token, "receipt vault symbol mismatch")
        );
        string memory initialWrappedSymbol = string.concat("wt", token.underlying);
        string memory wrappedSymbol = IERC20Metadata(wrappedTokenVault).symbol();
        if (keccak256(bytes(wrappedSymbol)) != keccak256(bytes(initialWrappedSymbol))) {
            assertEq(
                wrappedSymbol, renamedWrappedSymbol(initialWrappedSymbol), named(token, "wrapped vault symbol mismatch")
            );
        }
        assertEq(IERC4626(wrappedTokenVault).asset(), receiptVault, named(token, "wrapped vault asset mismatch"));
        assertEq(
            address(IReceiptVaultV3(payable(receiptVault)).receipt()), receipt, named(token, "receipt address mismatch")
        );
        // The receipt's manager controls mint/burn. If a prod receipt's
        // manager isn't its receipt vault, the vault can't mint receipts
        // when users deposit nor burn receipts when users withdraw —
        // every deposit and withdraw on this token would revert.
        assertEq(IReceiptV3(receipt).manager(), receiptVault, named(token, "receipt manager != receipt vault"));

        // All prod tokens on Base are behind the V1 OARV deployer's
        // beacons. The constants are the canonical source — the cross-check
        // that they match runtime resolution lives in
        // `testProdBeaconAddressesMatchConstants`.
        address receiptBeacon = LibProdDeployV1.STOX_RECEIPT_BEACON_V1;
        address receiptVaultBeacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        address wrappedVaultBeacon = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1;

        assertEq(beaconOf(receipt), receiptBeacon, named(token, "receipt beacon mismatch"));
        assertEq(beaconOf(receiptVault), receiptVaultBeacon, named(token, "receipt vault beacon mismatch"));
        assertEq(beaconOf(wrappedTokenVault), wrappedVaultBeacon, named(token, "wrapped vault beacon mismatch"));

        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                receiptBeacon, LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            named(token, "receipt beacon impl codehash mismatch")
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                receiptVaultBeacon, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            named(token, "receipt vault beacon impl codehash mismatch")
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                wrappedVaultBeacon, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            named(token, "wrapped vault beacon impl codehash mismatch")
        );

        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(receiptBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            named(token, "receipt beacon owner mismatch")
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(receiptVaultBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            named(token, "receipt vault beacon owner mismatch")
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(wrappedVaultBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            named(token, "wrapped vault beacon owner mismatch")
        );

        // Receipt vault transfers are gated on `certifiedUntil`. An expired
        // certification freezes all transfers on the affected token. Pin
        // that every prod vault is currently within its certification
        // window at the fork's block timestamp.
        assertFalse(
            ICertifiableV1(receiptVault).isCertificationExpired(), named(token, "receipt vault certification expired")
        );

        // Integrators (DEXes, indexers, UIs) read `decimals()` to scale
        // amounts. Drift from 18 silently shifts every off-chain
        // calculation by ten orders of magnitude per missing decimal.
        assertEq(IERC20Metadata(receiptVault).decimals(), 18, named(token, "receipt vault decimals != 18"));
        assertEq(IERC20Metadata(wrappedTokenVault).decimals(), 18, named(token, "wrapped vault decimals != 18"));

        // Per-class proxy codehash consistency. All receipt proxies are
        // BeaconProxy instances pointing at the same beacon, so their
        // runtime bytecode must be identical. Same for receipt vault
        // proxies and wrapped vault proxies. A divergent codehash means
        // a proxy was deployed through a different mechanism or with
        // different constructor args than its siblings.
        assertEq(
            keccak256(receipt.code),
            LibProdDeployV1.PROD_STOX_RECEIPT_PROXY_BASE_CODEHASH_V1,
            named(token, "receipt proxy codehash mismatch")
        );
        assertEq(
            keccak256(receiptVault.code),
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_PROXY_BASE_CODEHASH_V1,
            named(token, "receipt vault proxy codehash mismatch")
        );
        assertEq(
            keccak256(wrappedTokenVault.code),
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_PROXY_BASE_CODEHASH_V1,
            named(token, "wrapped vault proxy codehash mismatch")
        );

        // Wrapped vault claims (totalAssets) cannot exceed total receipt
        // vault shares minted (totalSupply). The wrapped vault's holdings
        // of the receipt vault are a subset of all minted receipt-vault
        // shares — others may hold receipt-vault shares directly.
        // Violation indicates an accounting bug.
        assertLe(
            IERC4626(wrappedTokenVault).totalAssets(),
            IERC20Metadata(receiptVault).totalSupply(),
            named(token, "wrapped vault totalAssets > receipt vault totalSupply")
        );
    }

    /// The first 20 Base token sets, each looked up by ticker in
    /// `productionTokensBase()`. Later entries may postdate the pinned block.
    function testProductionTokenSetsOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        string[20] memory tickers = [
            string("MSTR"),
            "TSLA",
            "COIN",
            "SPYM",
            "SIVR",
            "CRCL",
            "NVDA",
            "IAU",
            "PPLT",
            "AMZN",
            "BMNR",
            "IBHG",
            "SGOV",
            "QQQM",
            "VWO",
            "ARKK",
            "SPCX",
            "CEG",
            "DRAM",
            "TSM"
        ];
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        for (uint256 i = 0; i < tickers.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (keccak256(bytes(tokens[j].underlying)) == keccak256(bytes(tickers[i]))) {
                    checkTokenSet(tokens[j]);
                    found = true;
                    break;
                }
            }
            assertTrue(found, string.concat(tickers[i], " missing from productionTokensBase"));
        }
    }

    /// A prod V1 contract and the metamorphic-risk bitmap its code exposes.
    struct ProdV1Contract {
        string name;
        address account;
        uint256 metamorphicRisk;
    }

    /// The V1 implementations, deployers and beacons on Base.
    function prodV1Contracts() internal pure returns (ProdV1Contract[] memory) {
        // CREATE builds the beacons; DELEGATECALL comes from the OZ
        // Upgradeable / forwarder machinery.
        uint256 delegatecallOnly = uint256(1) << uint256(EVM_OP_DELEGATECALL);
        uint256 createAndDelegatecall = (uint256(1) << uint256(EVM_OP_CREATE)) | delegatecallOnly;
        ProdV1Contract[] memory contracts = new ProdV1Contract[](9);
        contracts[0] = ProdV1Contract("STOX_RECEIPT_IMPLEMENTATION", LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION, 0);
        contracts[1] = ProdV1Contract(
            "STOX_RECEIPT_VAULT_IMPLEMENTATION", LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION, delegatecallOnly
        );
        contracts[2] = ProdV1Contract(
            "STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION", LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION, 0
        );
        contracts[3] = ProdV1Contract(
            "OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER",
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            createAndDelegatecall
        );
        contracts[4] = ProdV1Contract(
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER",
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            createAndDelegatecall
        );
        contracts[5] = ProdV1Contract("STOX_UNIFIED_DEPLOYER", LibProdDeployV1.STOX_UNIFIED_DEPLOYER, 0);
        contracts[6] = ProdV1Contract("STOX_RECEIPT_BEACON_V1", LibProdDeployV1.STOX_RECEIPT_BEACON_V1, 0);
        contracts[7] = ProdV1Contract("STOX_RECEIPT_VAULT_BEACON_V1", LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, 0);
        contracts[8] =
            ProdV1Contract("STOX_WRAPPED_TOKEN_VAULT_BEACON_V1", LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1, 0);
        return contracts;
    }

    /// `foundry.toml` builds without CBOR metadata; the deployed V1 code
    /// must too.
    function testProdV1ContractsHaveNoCBOR() external {
        LibTestProd.createSelectForkBase(vm);
        ProdV1Contract[] memory contracts = prodV1Contracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            bytes memory code = contracts[i].account.code;
            assertTrue(code.length > 0, string.concat(contracts[i].name, " has no code"));
            assertFalse(
                LibExtrospectBytecode.tryTrimSolidityCBORMetadata(code),
                string.concat(contracts[i].name, " carries CBOR metadata")
            );
        }
    }

    /// Any metamorphic opcode appearing or disappearing forces a re-review.
    function testProdV1ContractsMetamorphicRiskPinned() external {
        LibTestProd.createSelectForkBase(vm);
        ProdV1Contract[] memory contracts = prodV1Contracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            assertEq(
                LibExtrospectMetamorphic.scanMetamorphicRisk(contracts[i].account.code),
                contracts[i].metamorphicRisk,
                string.concat(contracts[i].name, " metamorphic surface drifted")
            );
        }
    }

    /// Mutation pin: `testProdV1ContractsHaveNoCBOR` returns clean (no revert),
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
    /// at `EXTROSPECT_0_1_0`.
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
        IExtrospectV1(EXTROSPECT_0_1_0).checkNoSolidityCBORMetadata(sentinel);
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
            beaconOf(LibTokenInvariants.MSTR_WRAPPED_TOKEN_VAULT),
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1,
            "wrapped vault beacon read from MSTR proxy slot drifted"
        );
    }

    /// A V1 beacon with the implementation it served at the pinned block and
    /// the one it serves at Base HEAD.
    struct ProdV1Beacon {
        string name;
        address beacon;
        address implementationAtPinnedBlock;
        address implementationAtBaseHead;
    }

    /// The receipt and receipt-vault beacons serve 0.1.30 at HEAD after the
    /// fleet upgrade; the wrapped token vault beacon still serves 0.1.1.
    function prodV1Beacons() internal pure returns (ProdV1Beacon[] memory) {
        ProdV1Beacon[] memory beacons = new ProdV1Beacon[](3);
        beacons[0] = ProdV1Beacon(
            "STOX_RECEIPT_BEACON_V1",
            LibProdDeployV1.STOX_RECEIPT_BEACON_V1,
            LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION,
            LibProdDeployV4.STOX_RECEIPT_0_1_30
        );
        beacons[1] = ProdV1Beacon(
            "STOX_RECEIPT_VAULT_BEACON_V1",
            LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1,
            LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30
        );
        beacons[2] = ProdV1Beacon(
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_V1",
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1
        );
        return beacons;
    }

    /// Every V1 beacon is the same `UpgradeableBeacon` runtime, so a contract
    /// that merely mimics `implementation()` / `owner()` fails.
    function testProdV1BeaconsRuntimeCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        ProdV1Beacon[] memory beacons = prodV1Beacons();
        for (uint256 i = 0; i < beacons.length; i++) {
            assertEq(
                beacons[i].beacon.codehash,
                LibProdDeployV1.PROD_BEACON_BASE_RUNTIME_CODEHASH_V1,
                string.concat(beacons[i].name, " runtime codehash drifted")
            );
        }
    }

    /// HISTORICAL SNAPSHOT, not a drift detector: the V1 implementation
    /// constants describe a state Base was in at the pinned block.
    /// `isBeaconImplementationBytecode` only compares the impl's codehash;
    /// this pins its address.
    function testProdV1BeaconImplementationsAtPinnedBlock() external {
        LibTestProd.createSelectForkBase(vm);
        ProdV1Beacon[] memory beacons = prodV1Beacons();
        for (uint256 i = 0; i < beacons.length; i++) {
            assertEq(
                IBeacon(beacons[i].beacon).implementation(),
                beacons[i].implementationAtPinnedBlock,
                string.concat(beacons[i].name, ".implementation() drifted at the pinned block")
            );
        }
    }

    /// LIVE: an unreviewed `upgradeTo` on any in-use beacon fails here and
    /// nowhere else in this file.
    function testProdV1BeaconImplementationsAtBaseHead() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        ProdV1Beacon[] memory beacons = prodV1Beacons();
        for (uint256 i = 0; i < beacons.length; i++) {
            assertEq(
                IBeacon(beacons[i].beacon).implementation(),
                beacons[i].implementationAtBaseHead,
                string.concat(beacons[i].name, ".implementation() at Base HEAD is not the pinned live impl")
            );
        }
    }

    /// `checkTokenSet` trusts the OARV deployer's beacon getters, so a
    /// swapped deployer must fail loud.
    function testProdV1DeployersCodehash() external {
        LibTestProd.createSelectForkBase(vm);
        string[3] memory names = [
            string("OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER"),
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER",
            "STOX_UNIFIED_DEPLOYER"
        ];
        address[3] memory deployers = [
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV1.STOX_UNIFIED_DEPLOYER
        ];
        bytes32[3] memory codehashes = [
            LibProdDeployV1.PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1,
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1,
            LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1
        ];
        for (uint256 i = 0; i < deployers.length; i++) {
            assertEq(keccak256(deployers[i].code), codehashes[i], string.concat(names[i], " codehash drifted"));
        }

        vm.etch(LibProdDeployV1.STOX_UNIFIED_DEPLOYER, hex"00");
        assertNotEq(
            keccak256(LibProdDeployV1.STOX_UNIFIED_DEPLOYER.code),
            LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1,
            "swapped bytecode must not match the pinned codehash"
        );
    }
}
