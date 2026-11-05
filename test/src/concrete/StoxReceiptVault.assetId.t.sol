// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IAuthorizeV1} from "rain-vats-0.2.18/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.18/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
    OffchainAssetReceiptVaultConfigV3
} from "rain-vats-0.2.18/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {UnknownConfigVersion} from "rain-vats-0.2.18/src/abstract/OffchainAssetReceiptVault.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.6/src/concrete/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS
} from "rain-factory-deploy-0.2.6/src/generated/0_2_5/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    AssetIdAlreadySet,
    AssetIdNotInitializing,
    EmptyAssetId,
    NonCanonicalAssetIdMetadata,
    NonEmptyInitialName,
    NonEmptyInitialSymbol,
    UnknownAssetIdMetadata
} from "../../../src/error/ErrAssetId.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {LibAssetId, ASSET_ID_INITIALIZED, STOX_ASSET_ID_METADATA_V1_TAG} from "../../../src/lib/LibAssetId.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {ReentrantAssetIdReceipt} from "../../concrete/ReentrantAssetIdReceipt.sol";
import {HooklessStoxReceiptVault} from "../../concrete/HooklessStoxReceiptVault.sol";

/// @title StoxReceiptVaultAssetIdTest
/// @notice A vault is initialized with an empty name and symbol and an asset id in its metadata, which it stores once
/// and reports with `assetId()`; every other init reverts.
contract StoxReceiptVaultAssetIdTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    string internal constant ASSET_ID = "US67066G1040";

    function setUp() external {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        IAuthorizeV1 authorizer = IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl),
                    abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: OWNER})),
                    bytes32(uint256(uint160(address(impl))))
                )
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
    }

    function data(string memory name, string memory symbol, bytes memory metadata)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
            OffchainAssetReceiptVaultConfigV3({
                name: name,
                symbol: symbol,
                authority: AUTHORITY,
                rbacName: RBAC_NAME,
                receiptBeaconName: LibStoxConfig.RECEIPT_BEACON_NAME,
                metadata: metadata
            })
        );
    }

    function uninitialized() internal returns (StoxReceiptVault) {
        return StoxReceiptVault(payable(address(new BeaconProxy(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, ""))));
    }

    /// An uninitialized vault with OZ's `_initializing` flag set, as inside its `initialize`, so the facet's
    /// `initializeAssetId` can be called through the fallback directly.
    function initializing() internal returns (StoxReceiptVault) {
        StoxReceiptVault vault = uninitialized();
        bytes32 slot = keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1))
            & ~bytes32(uint256(0xff));
        // `_initializing` is the bool after the uint64 `_initialized`.
        vm.store(address(vault), slot, bytes32(uint256(1) << 64));
        return vault;
    }

    function upgradeVaultBeacon(address implementation) internal {
        vm.prank(LibProdDeployV1.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1).upgradeTo(implementation);
    }

    /// The vault stores and reports its asset id, starts nameless, and keeps the id through `setUnderlying`; the
    /// wrapper passes the id through.
    function testInitializeStoresTheAssetIdAndStartsNameless() external {
        StoxReceiptVault vault =
            LibTestDeploy.newVault(AUTHORITY, LibTestDeploy.vaultData(ASSET_ID, AUTHORITY, RBAC_NAME));
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), ASSET_ID, "asset id");
        assertEq(vault.name(), "", "name");
        assertEq(vault.symbol(), "", "symbol");

        StoxWrappedTokenVault wrapper = LibTestDeploy.newWrapper(AUTHORITY, address(vault));
        assertEq(wrapper.assetId(), ASSET_ID, "wrapper asset id");
        assertEq(wrapper.symbol(), "w", "wrapper symbol");
        assertEq(wrapper.name(), "Wrapped ", "wrapper name");

        vm.prank(OWNER);
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation");
        assertEq(vault.symbol(), "tNVDA", "renamed symbol");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)", "renamed name");
        assertEq(wrapper.symbol(), "NVDAs", "renamed wrapper symbol");
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), ASSET_ID, "asset id after rename");
        assertEq(wrapper.assetId(), ASSET_ID, "wrapper asset id after rename");
    }

    /// `AssetIdSet` fires once, from the vault, naming the factory that called `initialize`.
    function testAssetIdSetFiresOnce() external {
        vm.recordLogs();
        StoxReceiptVault vault =
            LibTestDeploy.newVault(AUTHORITY, LibTestDeploy.vaultData(ASSET_ID, AUTHORITY, RBAC_NAME));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IStoxAssetIdV1.AssetIdSet.selector) {
                count++;
                assertEq(logs[i].emitter, address(vault), "emitter");
                assertEq(logs[i].topics[1], bytes32(uint256(uint160(CLONE_FACTORY_ADDRESS))), "sender");
                assertEq(abi.decode(logs[i].data, (string)), ASSET_ID, "asset id");
            }
        }
        assertEq(count, 1, "once");
    }

    function testInitializeRejectsANonEmptyName(string memory name) external {
        vm.assume(bytes(name).length > 0);
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(NonEmptyInitialName.selector);
        vault.initialize(data(name, "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    function testInitializeRejectsANonEmptySymbol(string memory symbol) external {
        vm.assume(bytes(symbol).length > 0);
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(NonEmptyInitialSymbol.selector);
        vault.initialize(data("", symbol, LibAssetId.encodeMetadata(ASSET_ID)));
    }

    function testInitializeRejectsAnEmptyAssetId() external {
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(EmptyAssetId.selector);
        vault.initialize(data("", "", LibAssetId.encodeMetadata("")));
    }

    function testInitializeRejectsEmptyMetadata() external {
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(abi.encodeWithSelector(UnknownAssetIdMetadata.selector, bytes32(0)));
        vault.initialize(data("", "", ""));
    }

    function testInitializeRejectsAnUnknownMetadataTag(bytes32 tag) external {
        vm.assume(tag != STOX_ASSET_ID_METADATA_V1_TAG);
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(abi.encodeWithSelector(UnknownAssetIdMetadata.selector, tag));
        vault.initialize(data("", "", abi.encode(tag, ASSET_ID)));
    }

    /// Trailing bytes after the canonical encoding.
    function testInitializeRejectsTrailingMetadataBytes(bytes memory trailing) external {
        vm.assume(trailing.length > 0);
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(NonCanonicalAssetIdMetadata.selector);
        vault.initialize(data("", "", bytes.concat(LibAssetId.encodeMetadata(ASSET_ID), trailing)));
    }

    /// An in-bounds string offset other than the canonical 0x40.
    function testInitializeRejectsAnAlternateMetadataOffset() external {
        StoxReceiptVault vault = uninitialized();
        bytes memory metadata = abi.encodePacked(
            STOX_ASSET_ID_METADATA_V1_TAG,
            uint256(0x60),
            bytes32(0),
            uint256(bytes(ASSET_ID).length),
            // casting to 'bytes32' is safe because ASSET_ID is 12 bytes, so it is right-padded, not truncated.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32(bytes(ASSET_ID))
        );
        vm.expectRevert(NonCanonicalAssetIdMetadata.selector);
        vault.initialize(data("", "", metadata));
    }

    /// An out-of-bounds string offset makes `abi.decode` revert without data.
    function testInitializeRejectsAnOutOfBoundsMetadataOffset() external {
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(bytes(""));
        vault.initialize(data("", "", abi.encodePacked(STOX_ASSET_ID_METADATA_V1_TAG, uint256(0x1000))));
    }

    /// With no facet code at the pinned address, `initialize` reverts instead of producing a vault with no asset id.
    /// On chain the delegatecall succeeds with no return data and the hook reverts without data. Forge with traces on
    /// (`forge test -vvv`, as CI runs it) reports its own error for a delegatecall to an account with no code, so any
    /// revert is accepted here.
    function testInitializeRevertsWithoutFacet() external {
        StoxReceiptVault vault = uninitialized();
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "");
        vm.expectRevert();
        vault.initialize(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    /// A facet that succeeds with no return data, as a delegatecall to an account with no code does on chain, makes
    /// the hook revert without data.
    function testInitializeRevertsWhenTheFacetReturnsNothing() external {
        StoxReceiptVault vault = uninitialized();
        // STOP: succeeds and returns no data.
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, hex"00");
        vm.expectRevert(bytes(""));
        vault.initialize(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    /// Outside `initialize`, before or after it, the facet refuses to set the asset id.
    function testInitializeAssetIdRefusesOutsideInitialize() external {
        bytes memory initData = data("", "", LibAssetId.encodeMetadata("OTHER"));
        StoxReceiptVault fresh = uninitialized();
        vm.expectRevert(AssetIdNotInitializing.selector);
        StoxCorporateActionsFacet(address(fresh)).initializeAssetId(initData);

        StoxReceiptVault vault =
            LibTestDeploy.newVault(AUTHORITY, LibTestDeploy.vaultData(ASSET_ID, AUTHORITY, RBAC_NAME));
        vm.expectRevert(AssetIdNotInitializing.selector);
        StoxCorporateActionsFacet(address(vault)).initializeAssetId(initData);
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), ASSET_ID);
    }

    function testStandaloneFacetRefusesDirectCalls() external {
        StoxCorporateActionsFacet facet =
            StoxCorporateActionsFacet(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE);
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.assetId();
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        facet.initializeAssetId(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    /// `initialize` inside a `multicall` delegatecalls the vault with the inner calldata, so the hook still forwards
    /// `initialize(bytes)` calldata.
    function testInitializeThroughMulticallStoresTheAssetId() external {
        StoxReceiptVault vault = uninitialized();
        bytes memory initData = data("", "", LibAssetId.encodeMetadata(ASSET_ID));
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(vault.initialize, (initData));
        vm.expectCall(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
            abi.encodeCall(StoxCorporateActionsFacet.initializeAssetId, (initData))
        );
        vault.multicall(calls);
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), ASSET_ID);
    }

    /// A receipt that sets another asset id while its vault initializes makes the vault's own hook refuse, so the
    /// worst case is a failed deploy, never a wrong id.
    function testReentrantAssetIdFromTheReceiptReverts() external {
        address reentrant = address(new ReentrantAssetIdReceipt());
        vm.prank(LibProdDeployV1.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(LibProdDeployV1.STOX_RECEIPT_BEACON_V1).upgradeTo(reentrant);
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(AssetIdAlreadySet.selector);
        vault.initialize(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    /// A vault initialized named, before the hook existed, reports no asset id after the upgrade to the hook and can
    /// never be given one; it still renames.
    function testLegacyVaultReportsNoAssetIdAndCannotSetOne() external {
        address hookless = address(new HooklessStoxReceiptVault());
        upgradeVaultBeacon(hookless);
        StoxReceiptVault vault = LibTestDeploy.newVault(AUTHORITY, data("Legacy ST0x", "tLEG", ""));
        assertEq(vault.symbol(), "tLEG");
        upgradeVaultBeacon(LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE);

        assertEq(IStoxAssetIdV1(address(vault)).assetId(), "");
        vm.expectRevert(AssetIdNotInitializing.selector);
        StoxCorporateActionsFacet(address(vault)).initializeAssetId(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
        assertEq(LibTestDeploy.newWrapper(AUTHORITY, address(vault)).assetId(), "");

        vm.prank(OWNER);
        IStoxUnderlyingV1(address(vault)).setUnderlying("LEG", "Legacy");
        assertEq(vault.symbol(), "tLEG");
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), "");
    }

    /// The wrapper's passthrough never reverts on an asset without `assetId()`.
    function testWrapperOfAnAssetWithoutAssetIdReportsEmpty() external {
        MockERC20 asset = new MockERC20();
        StoxWrappedTokenVault wrapper = LibTestDeploy.newWrapper(AUTHORITY, address(asset));
        assertEq(wrapper.assetId(), "");
    }

    /// The hook delegatecalls the facet's `initializeAssetId` with exactly the vault's `initialize` argument.
    function testHookForwardsTheInitializeArgumentToTheFacet() external {
        bytes memory initData = data("", "", LibAssetId.encodeMetadata(ASSET_ID));
        StoxReceiptVault vault = uninitialized();
        vm.expectCall(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE,
            abi.encodeCall(StoxCorporateActionsFacet.initializeAssetId, (initData))
        );
        vault.initialize(initData);
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), ASSET_ID);
    }

    /// The vault trusts a pinned facet that returns exactly one word, whatever the word: the return value is not
    /// checked (an accepted trust boundary). A facet that returns any other size reverts the init.
    function testHookChecksOnlyTheReturnSize() external {
        address facet = LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE;
        // Returns one zero word.
        vm.etch(facet, hex"60206000f3");
        StoxReceiptVault vault = uninitialized();
        vault.initialize(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
        assertEq(vault.symbol(), "");

        // Returns two words.
        vm.etch(facet, hex"60406000f3");
        vault = uninitialized();
        vm.expectRevert(abi.encodePacked(bytes32(0), bytes32(0)));
        vault.initialize(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    /// A facet call that reverts with exactly one word still reverts the init: the hook checks the success flag, not
    /// only the return size.
    function testHookRevertsWhenTheFacetRevertsWithOneWord() external {
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, hex"60206000fd");
        StoxReceiptVault vault = uninitialized();
        vm.expectRevert(abi.encodePacked(bytes32(0)));
        vault.initialize(data("", "", LibAssetId.encodeMetadata(ASSET_ID)));
    }

    /// The facet checks the config tag itself, so a call that reaches it with another tag while the vault
    /// initializes is refused.
    function testInitializeAssetIdRefusesAnUnknownConfigTag(bytes32 tag) external {
        vm.assume(tag != OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG);
        StoxReceiptVault vault = initializing();
        (, OffchainAssetReceiptVaultConfigV3 memory config) =
            abi.decode(data("", "", LibAssetId.encodeMetadata(ASSET_ID)), (bytes32, OffchainAssetReceiptVaultConfigV3));
        vm.expectRevert(abi.encodeWithSelector(UnknownConfigVersion.selector, tag));
        StoxCorporateActionsFacet(address(vault)).initializeAssetId(abi.encode(tag, config));
    }

    /// The facet returns `ASSET_ID_INITIALIZED` once it has stored the id.
    function testInitializeAssetIdReturnsItsSuccessWord() external {
        StoxReceiptVault vault = initializing();
        assertEq(
            StoxCorporateActionsFacet(address(vault))
                .initializeAssetId(data("", "", LibAssetId.encodeMetadata(ASSET_ID))),
            ASSET_ID_INITIALIZED
        );
        assertEq(IStoxAssetIdV1(address(vault)).assetId(), ASSET_ID);
    }
}
