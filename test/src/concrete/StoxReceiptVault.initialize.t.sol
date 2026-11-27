// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin-contracts-5.7.0/utils/introspection/IERC165.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Base64} from "@openzeppelin-contracts-5.7.0/utils/Base64.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config
} from "rain-vats-0.2.25/src/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {VerifyAlwaysApproved} from "rain-verify-interface-0.1.0/src/concrete/VerifyAlwaysApproved.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.14/src/concrete/CloneFactory.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    AuthorizerMissingCorporateActionAdmin,
    CorporateActionsFacetNotDeployed
} from "../../../src/error/ErrCorporateAction.sol";
import {
    IOffchainAssetReceiptVaultV1,
    OffchainAssetReceiptVaultConfigV3
} from "rain-vats-0.2.25/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../src/lib/LibCorporateAction.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibRainDeploy} from "rain-deploy-0.1.41/src/lib/LibRainDeploy.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {
    IStoxTokenConfigV1,
    StoxTokenConfigV1,
    AssetId,
    AssetIdKind,
    STOX_TOKEN_CONFIG_V1_TAG
} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {STOX_TOKEN_CONFIG_STORAGE_LOCATION} from "../../../src/lib/LibStoxTokenConfig.sol";
import {StoxTokenAlreadyInitialized} from "../../../src/error/ErrStoxTokenConfig.sol";
import {Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";

/// @title StoxReceiptVault initialize
/// @notice A vault built by the clone factory resolves its authorizer from
/// the registry RBAC and holds it to the corporate-action admin check, and
/// its receipt's metadata names the off-chain asset.
contract StoxReceiptVaultInitializeTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");

    function setUp() external {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
    }

    function _newCorporateActionsAuthorizer() internal returns (IAuthorizeV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        return IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl), LibTestDeploy.authorizerData(vm, OWNER), bytes32(uint256(uint160(address(impl))))
                )
        );
    }

    function _newPaymentMintAuthorizer() internal returns (IAuthorizeV1) {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 impl =
            new StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1();
        return IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl),
                    abi.encode(
                        OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config({
                        receiptVault: address(this),
                        verify: address(new VerifyAlwaysApproved()),
                        owner: OWNER,
                        paymentToken: address(new MockERC20()),
                        maxSharesSupply: 1e27
                    })
                    ),
                    bytes32(uint256(uint160(address(impl))))
                )
        );
    }

    function _uninitializedVault() internal returns (StoxReceiptVault) {
        return StoxReceiptVault(payable(address(new BeaconProxy(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, ""))));
    }

    function _data() internal pure returns (bytes memory) {
        return LibTestDeploy.vaultData("US0378331005", "TEST", "Test", AUTHORITY, RBAC_NAME);
    }

    /// The RBAC's authorizer and owner are installed, replacing the vault
    /// itself, which `_initialize` installs first.
    function testInitializeInstallsTheRbacAuthorizer() external {
        IAuthorizeV1 authorizer = _newCorporateActionsAuthorizer();
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
        StoxReceiptVault vault = LibTestDeploy.newVault(AUTHORITY, _data());
        assertEq(address(vault.authorizer()), address(authorizer));
        assertEq(vault.owner(), OWNER);
    }

    /// A delegatecall into empty code succeeds, so the missing facet is
    /// named instead of failing the decode without a reason.
    function testInitializeRevertsWithoutFacet() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        vm.etch(facet, "");
        StoxReceiptVault vault = _uninitializedVault();
        vm.expectRevert(abi.encodeWithSelector(CorporateActionsFacetNotDeployed.selector, facet));
        vault.initialize(_data());
    }

    /// An RBAC authorizer without a corporate-action admin is refused at
    /// initialize, as it is at `setAuthorizer`.
    function testInitializeRejectsAnRbacAuthorizerMissingAnAdmin() external {
        address bad = makeAddr("authorizer-without-schedule-admin");
        vm.etch(bad, hex"00");
        vm.mockCall(
            bad,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(bytes32(0))
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, IAuthorizeV1(bad));
        StoxReceiptVault vault =
            StoxReceiptVault(payable(address(new BeaconProxy(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, ""))));
        vm.expectRevert(
            abi.encodeWithSelector(AuthorizerMissingCorporateActionAdmin.selector, bad, SCHEDULE_CORPORATE_ACTION)
        );
        vault.initialize(_data());
    }

    /// Initialization installs the vault first, then the bound authorizer,
    /// which is what the token ends with.
    function testInitializedTokenEndsWithTheBoundAuthorizerNotItself() external {
        IAuthorizeV1 authorizer = _newCorporateActionsAuthorizer();
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
        vm.recordLogs();
        StoxReceiptVault vault = LibTestDeploy.newVault(AUTHORITY, _data());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory installed = new address[](logs.length);
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == IAuthorizeV1.AuthorizerSet.selector) {
                (, address set) = abi.decode(logs[i].data, (address, address));
                installed[count++] = set;
            }
        }
        assertEq(count, 2);
        assertEq(installed[0], address(vault));
        assertEq(installed[1], address(authorizer));
        assertEq(address(vault.authorizer()), address(authorizer));
    }

    /// A bound PaymentMint authorizer has no schedule admin, so initialize
    /// refuses it.
    function testInitializeRejectsABoundPaymentMintAuthorizer() external {
        IAuthorizeV1 bad = _newPaymentMintAuthorizer();
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, bad);
        StoxReceiptVault vault = _uninitializedVault();
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthorizerMissingCorporateActionAdmin.selector, address(bad), SCHEDULE_CORPORATE_ACTION
            )
        );
        vault.initialize(_data());
    }

    /// A bound authorizer with a schedule admin but no cancel admin is
    /// refused at initialize on the cancel role.
    function testInitializeRejectsABoundAuthorizerMissingTheCancelAdmin() external {
        address bad = makeAddr("authorizer-without-cancel-admin");
        vm.etch(bad, hex"00");
        vm.mockCall(
            bad,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IAuthorizeV1).interfaceId),
            abi.encode(true)
        );
        vm.mockCall(
            bad,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(bytes32(uint256(1)))
        );
        vm.mockCall(
            bad,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, CANCEL_CORPORATE_ACTION),
            abi.encode(bytes32(0))
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, IAuthorizeV1(bad));
        StoxReceiptVault vault = _uninitializedVault();
        vm.expectRevert(
            abi.encodeWithSelector(AuthorizerMissingCorporateActionAdmin.selector, bad, CANCEL_CORPORATE_ACTION)
        );
        vault.initialize(_data());
    }

    /// The kind byte is dirtied first, since ISIN is the zero value.
    function testInitializeStoresAndEmitsTheIsinKind() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceiptVault vault = _uninitializedVault();
        bytes32 kindSlot = STOX_TOKEN_CONFIG_STORAGE_LOCATION;
        vm.store(address(vault), kindSlot, bytes32(uint256(0xff)));

        vm.recordLogs();
        vault.initialize(_data());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(uint8(uint256(vm.load(address(vault), kindSlot))), uint8(AssetIdKind.ISIN), "stored kind");
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(vault)
                    && logs[i].topics[0] == IStoxTokenConfigV1.StoxTokenInitialized.selector
            ) {
                StoxTokenConfigV1 memory config = abi.decode(logs[i].data, (StoxTokenConfigV1));
                assertEq(uint8(config.assetId.kind), uint8(AssetIdKind.ISIN), "emitted kind");
                count++;
            }
        }
        assertEq(count, 1, "one StoxTokenInitialized");
    }

    /// The same vault then accepts the ISIN data, so the kind word alone is
    /// refused.
    function testFuzzInitializeRefusesANonIsinKindWord(uint256 kind) external {
        kind = bound(kind, uint256(AssetIdKind.ISIN) + 1, type(uint256).max);
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceiptVault vault = _uninitializedVault();
        bytes memory data = _data();
        // Tag, config offset, then the config head of eight words; the
        // assetId tuple heads the tail and its first word is the kind.
        uint256 assetIdOffset;
        uint256 isinWord;
        assembly ("memory-safe") {
            let config := add(data, 0x60)
            assetIdOffset := mload(config)
            let kindPointer := add(config, assetIdOffset)
            isinWord := mload(kindPointer)
            mstore(kindPointer, kind)
        }
        assertEq(assetIdOffset, 0x100, "assetId offset");
        assertEq(isinWord, uint256(AssetIdKind.ISIN), "kind word");

        // abi.decode's enum check reverts without data.
        vm.expectRevert(bytes(""));
        vault.initialize(data);

        vault.initialize(_data());
    }

    /// The same vault then accepts the ISIN data, so the region word alone
    /// is refused.
    function testFuzzInitializeRefusesARegionWordPastEu(uint256 region) external {
        region = bound(region, uint256(Region.EU) + 1, type(uint256).max);
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceiptVault vault = _uninitializedVault();
        bytes memory data = _data();
        // Tag, config offset, then the config head: assetId offset,
        // listingTicker offset, listingName offset, region.
        uint256 regionWord;
        assembly ("memory-safe") {
            regionWord := mload(add(data, 0xc0))
            mstore(add(data, 0xc0), region)
        }
        assertEq(regionWord, uint256(Region.US), "region word");

        // abi.decode's enum check reverts without data.
        vm.expectRevert(bytes(""));
        vault.initialize(data);

        vault.initialize(_data());
    }

    /// Authority, RBAC name, receipt-beacon name and metadata reach rain-vats
    /// unchanged, beside the name and symbol derived from the listing.
    function testInitializePassesTheV3ConfigThrough() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxTokenConfigV1 memory config = _config("US0378331005", "AAPL", "Apple Inc.", Region.US);
        config.metadata = abi.encode(keccak256("st0x.test.metadata"), bytes("payload"));
        StoxReceiptVault vault = _uninitializedVault();

        vm.recordLogs();
        vault.initialize(abi.encode(STOX_TOKEN_CONFIG_V1_TAG, config));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(vault)
                    && logs[i].topics[0] == IOffchainAssetReceiptVaultV1.OffchainAssetReceiptVaultInitializedV3.selector
            ) {
                (, OffchainAssetReceiptVaultConfigV3 memory v3,,) =
                    abi.decode(logs[i].data, (address, OffchainAssetReceiptVaultConfigV3, address, address));
                assertEq(v3.name, "Apple Inc. (ST0x)");
                assertEq(v3.symbol, "tAAPL");
                assertEq(v3.authority, AUTHORITY);
                assertEq(v3.rbacName, RBAC_NAME);
                assertEq(v3.receiptBeaconName, LibStoxConfig.RECEIPT_BEACON_NAME);
                assertEq(v3.metadata, config.metadata);
                count++;
            }
        }
        assertEq(count, 1, "one OffchainAssetReceiptVaultInitializedV3");
    }

    function _config(string memory assetId, string memory listingTicker, string memory listingName, Region region)
        internal
        pure
        returns (StoxTokenConfigV1 memory)
    {
        return StoxTokenConfigV1({
            assetId: AssetId({kind: AssetIdKind.ISIN, id: assetId}),
            listingTicker: listingTicker,
            listingName: listingName,
            region: region,
            authority: AUTHORITY,
            rbacName: RBAC_NAME,
            receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
            metadata: ""
        });
    }

    function _loadString(address account, uint256 slot) internal view returns (string memory) {
        uint256 word = uint256(vm.load(account, bytes32(slot)));
        if (word & 1 == 0) {
            bytes memory inlined = new bytes((word & 0xff) / 2);
            for (uint256 i = 0; i < inlined.length; i++) {
                inlined[i] = bytes32(word)[i];
            }
            return string(inlined);
        }
        bytes memory spilled = new bytes((word - 1) / 2);
        uint256 base = uint256(keccak256(abi.encode(slot)));
        for (uint256 i = 0; i < spilled.length; i++) {
            spilled[i] = vm.load(account, bytes32(base + i / 32))[i % 32];
        }
        return string(spilled);
    }

    /// The region byte is dirtied first, since US is the zero value.
    function _assertInitializeStoresAndEmits(StoxTokenConfigV1 memory config) internal {
        StoxReceiptVault vault = _uninitializedVault();
        uint256 location = uint256(STOX_TOKEN_CONFIG_STORAGE_LOCATION);
        vm.store(address(vault), bytes32(location + 4), bytes32(uint256(0xff)));

        vm.recordLogs();
        vault.initialize(abi.encode(STOX_TOKEN_CONFIG_V1_TAG, config));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_loadString(address(vault), location + 1), config.assetId.id, "stored assetId");
        assertEq(_loadString(address(vault), location + 2), config.listingTicker, "stored listingTicker");
        assertEq(_loadString(address(vault), location + 3), config.listingName, "stored listingName");
        assertEq(uint8(uint256(vm.load(address(vault), bytes32(location + 4)))), uint8(config.region), "stored region");
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(vault)
                    && logs[i].topics[0] == IStoxTokenConfigV1.StoxTokenInitialized.selector
            ) {
                StoxTokenConfigV1 memory emitted = abi.decode(logs[i].data, (StoxTokenConfigV1));
                assertEq(logs[i].topics[1], bytes32(uint256(uint160(address(this)))), "emitted sender");
                assertEq(abi.encode(emitted), abi.encode(config), "emitted config");
                count++;
            }
        }
        assertEq(count, 1, "one StoxTokenInitialized");
    }

    /// The second name is longer than a storage word.
    function testInitializeStoresAndEmitsTheListing() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        _assertInitializeStoresAndEmits(_config("US0378331005", "AAPL", "Apple Inc.", Region.US));
        _assertInitializeStoresAndEmits(
            _config("US78464A8541", "SPYM", "State Street SPDR Portfolio S&P 500 ETF", Region.EU)
        );
    }

    function testInitializeRefusesAnInitializedToken() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceiptVault vault = LibTestDeploy.newVault(AUTHORITY, _data());
        vm.expectRevert(abi.encodeWithSelector(StoxTokenAlreadyInitialized.selector));
        vault.initialize(LibTestDeploy.vaultData("US0378331005", "AAPL", "Apple Inc.", AUTHORITY, RBAC_NAME));
    }

    function testInitializeStoxTokenThroughTheFallbackRefusesAnInitializedToken() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceiptVault vault = LibTestDeploy.newVault(AUTHORITY, _data());
        vm.expectRevert(abi.encodeWithSelector(StoxTokenAlreadyInitialized.selector));
        IStoxTokenConfigV1(address(vault))
            .initializeStoxToken(LibTestDeploy.vaultData("US0378331005", "AAPL", "Apple Inc.", AUTHORITY, RBAC_NAME));
    }

    /// Once initialized, the token cannot reinstall itself: it has no
    /// `getRoleAdmin`, and its bound authorizer stays.
    function testInitializedTokenRejectsItselfAsAuthorizer() external {
        IAuthorizeV1 authorizer = _newCorporateActionsAuthorizer();
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
        StoxReceiptVault vault = LibTestDeploy.newVault(AUTHORITY, _data());
        vm.prank(OWNER);
        vm.expectRevert(bytes(""));
        vault.setAuthorizer(IAuthorizeV1(address(vault)));
        assertEq(address(vault.authorizer()), address(authorizer));
    }

    /// Outside initialization the vault is no exemption: it lacks
    /// `getRoleAdmin`, so installing it as its own authorizer reverts.
    function testSetAuthorizerRejectsTheVaultItself() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        vm.prank(OWNER);
        vm.expectRevert();
        vault.setAuthorizer(IAuthorizeV1(address(vault)));
        assertEq(address(vault.authorizer()), address(0));
    }

    /// The receipt's `uri` is vats' receipt JSON with the off-chain asset
    /// named, where the generic receipt reads `asset()` at `address(0)`.
    function testReceiptUriNamesTheOffchainAsset() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceipt receipt = StoxReceipt(address(LibTestDeploy.newVault(AUTHORITY, _data()).receipt()));
        assertEq(
            receipt.uri(0),
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        "{\"decimals\":18,\"description\":\"1 of these receipts can be burned alongside 1 tTEST to redeem the underlying off-chain asset from the vault.\",\"name\":\"tTEST Receipt\"}"
                    )
                )
            )
        );
    }
}
