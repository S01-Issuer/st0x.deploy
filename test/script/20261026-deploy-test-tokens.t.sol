// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.2.2/src/lib/LibCloneFactoryDeploy.sol";
import {
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.2/src/generated/0_2_2/CloneFactory.sol";
import {ICloneableFactoryV6} from "rain-factory-0.2.5/src/interface/ICloneableFactoryV6.sol";
import {ICloneableV2} from "rain-factory-0.2.5/src/interface/ICloneableV2.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibConfigRegistryDeploy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.9/src/interface/IAuthorizeV1.sol";
import {IAuthorizableV1} from "rain-vats-0.2.9/src/interface/IAuthorizableV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.9/src/interface/IReceiptVaultV3.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.9/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.5/src/lib/LibICloneableFactoryV5.sol";
import {OffchainAssetReceiptVaultRbacV1} from "rain-vats-0.2.9/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";

import {
    BeaconBindingMismatch,
    BeaconImplementationMismatch,
    DependencyNotDeployed,
    DeployTestTokens,
    RbacAuthoriserMismatch,
    RbacOwnerMismatch,
    TestTokenAuthoriserMismatch,
    TestTokenNotLanded,
    TestTokenOwnerMismatch
} from "../../script/20261026-deploy-test-tokens.s.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxCorporateActionsFacet} from "../../src/concrete/StoxCorporateActionsFacet.sol";
import {IST0xVaultBeaconSet} from "../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdBeacons0_1_1} from "../../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {Region} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxTestTokens, TestTokenAddresses} from "../../src/lib/LibStoxTestTokens.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";

/// @title DeployTestTokensTest
/// @notice The US and EU test tokens on a local EVM standing in for each
/// production chain: each chain's own beacons, timelock and region authorisers
/// bound under the root authority, as on chain.
contract DeployTestTokensTest is Test {
    DeployTestTokens internal script;

    function setUp() external {
        script = new DeployTestTokens();
    }

    /// The chain's production state, local: its beacons serving the candidate
    /// implementations, owned by its timelock; the factory and registry; a
    /// real authoriser at each region's pin; and the root authority's beacon
    /// and RBAC bindings.
    function setUpChain(uint256 chainId) internal {
        setUpChainWithoutRbac(chainId);
        bindRbac(
            LibStoxConfig.US_RBAC_NAME,
            LibTimelockInvariants.timelockForChainId(chainId),
            LibAuthoriserInvariants.authoriserForChainId(chainId)
        );
        bindRbac(
            LibStoxConfig.EU_RBAC_NAME,
            LibTimelockInvariants.timelockForChainId(chainId),
            LibAuthoriserInvariants.euAuthoriserForChainId(chainId)
        );
    }

    /// `setUpChain` with neither region's RBAC bound.
    function setUpChainWithoutRbac(uint256 chainId) internal {
        vm.chainId(chainId);
        LibTestDeploy.deployImplementations(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);

        address receiptBeacon;
        address vaultBeacon;
        address wrapperBeacon;
        if (LibBeaconInvariants.runsBaseBeaconSet(chainId)) {
            receiptBeacon = LibProdDeployV1.STOX_RECEIPT_BEACON_V1;
            vaultBeacon = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
            wrapperBeacon = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1;
        } else {
            receiptBeacon = makeAddr("receipt-beacon-0.1.1");
            vaultBeacon = makeAddr("vault-beacon-0.1.1");
            wrapperBeacon = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1;
            address deployer = LibProdBeacons0_1_1.beaconSetDeployer();
            vm.etch(deployer, hex"00");
            vm.mockCall(deployer, abi.encodeCall(IST0xVaultBeaconSet.iReceiptBeacon, ()), abi.encode(receiptBeacon));
            vm.mockCall(
                deployer,
                abi.encodeCall(IST0xVaultBeaconSet.iOffchainAssetReceiptVaultBeacon, ()),
                abi.encode(vaultBeacon)
            );
        }
        LibTestDeploy.placeBeacon(vm, receiptBeacon, LibProdDeployCurrent.STOX_RECEIPT, timelock);
        LibTestDeploy.placeBeacon(vm, vaultBeacon, LibProdDeployCurrent.STOX_RECEIPT_VAULT, timelock);
        LibTestDeploy.placeBeacon(vm, wrapperBeacon, LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT, timelock);
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(chainId);
        assertEq(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], receiptBeacon);
        assertEq(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], vaultBeacon);
        assertEq(beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX], wrapperBeacon);

        vm.etch(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS, CLONE_FACTORY_RUNTIME_CODE);
        LibTestDeploy.etchConfigRegistry(vm);

        placeAuthoriser(LibAuthoriserInvariants.authoriserForChainId(chainId));
        placeAuthoriser(LibAuthoriserInvariants.euAuthoriserForChainId(chainId));

        address root = LibStoxConfig.ROOT_AUTHORITY;
        LibTestDeploy.bind(vm, root, LibStoxConfig.RECEIPT_BEACON_NAME, abi.encode(receiptBeacon));
        LibTestDeploy.bind(vm, root, LibStoxConfig.VAULT_BEACON_NAME, abi.encode(vaultBeacon));
        LibTestDeploy.bind(vm, root, LibStoxConfig.WRAPPER_BEACON_NAME, abi.encode(wrapperBeacon));
    }

    /// An initialized `StoxOffchainAssetReceiptVaultAuthorizerV1` clone at
    /// `at`, administered by the chain's Safe.
    function placeAuthoriser(address at) internal {
        if (at.code.length != 0) return;
        address impl = address(new StoxOffchainAssetReceiptVaultAuthorizerV1());
        bytes memory creation = LibICloneableFactoryV5.cloneCreationCode(impl);
        address clone;
        assembly ("memory-safe") {
            clone := create(0, add(creation, 0x20), mload(creation))
        }
        vm.etch(at, clone.code);
        ICloneableV2(at)
            .initialize(
                abi.encode(
                    OffchainAssetReceiptVaultAuthorizerV1Config({
                    initialAdmin: LibSafeInvariants.safeForChainId(block.chainid)
                })
                )
            );
    }

    function bindRbac(bytes32 name, address owner, address authorizer) internal {
        LibTestDeploy.bind(
            vm,
            LibStoxConfig.ROOT_AUTHORITY,
            name,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: IAuthorizeV1(authorizer)}))
        );
    }

    function factory() internal pure returns (ICloneableFactoryV6) {
        return ICloneableFactoryV6(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS);
    }

    /// The region's addresses as the factory derives them: the token from its
    /// init data under the vault beacon name, and the receipt and wrapper from
    /// `abi.encode(token)` under their names.
    function predicted(Region region) internal view returns (TestTokenAddresses memory) {
        address registry = LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS;
        address root = LibStoxConfig.ROOT_AUTHORITY;
        address token = factory()
            .predictRegistryBeaconProxyAddress(
                registry, root, LibStoxConfig.VAULT_BEACON_NAME, LibStoxTestTokens.vaultData(region), bytes32(0)
            );
        return TestTokenAddresses({
            token: token,
            receipt: factory()
                .predictRegistryBeaconProxyAddress(
                    registry, root, LibStoxConfig.RECEIPT_BEACON_NAME, abi.encode(token), bytes32(0)
                ),
            wrapper: factory()
                .predictRegistryBeaconProxyAddress(
                    registry, root, LibStoxConfig.WRAPPER_BEACON_NAME, abi.encode(token), bytes32(0)
                )
        });
    }

    function assertRegionLanded(Region region, string memory name, string memory symbol) internal view {
        TestTokenAddresses memory pinned = LibStoxTestTokens.addresses(region);
        assertEq(IERC20Metadata(pinned.token).name(), name, "name");
        assertEq(IERC20Metadata(pinned.token).symbol(), symbol, "symbol");
        assertEq(address(IReceiptVaultV3(payable(pinned.token)).receipt()), pinned.receipt, "receipt");
        assertEq(IERC4626(pinned.wrapper).asset(), pinned.token, "wrapper asset");
        assertEq(Ownable(pinned.token).owner(), LibTimelockInvariants.timelockForChainId(block.chainid), "owner");
        address authoriser = region == Region.EU
            ? LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
            : LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        assertEq(address(IAuthorizableV1(pinned.token).authorizer()), authoriser, "authoriser");
    }

    /// Each pin is the address the factory derives.
    function testPinsAreTheFactoryDerivation() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        for (uint256 i = 0; i < 2; i++) {
            Region region = Region(i);
            TestTokenAddresses memory pinned = LibStoxTestTokens.addresses(region);
            TestTokenAddresses memory derived = predicted(region);
            assertEq(pinned.token, derived.token, "token");
            assertEq(pinned.receipt, derived.receipt, "receipt");
            assertEq(pinned.wrapper, derived.wrapper, "wrapper");
        }
        assertTrue(LibStoxTestTokens.US_TOKEN != LibStoxTestTokens.EU_TOKEN, "regions share a token");
    }

    function checkRunOnChain(uint256 chainId) internal {
        setUpChain(chainId);
        script.run();
        assertRegionLanded(Region.US, "US Test ST0x", "tUSTEST");
        assertRegionLanded(Region.EU, "EU Test ST0x", "tEUTEST");
    }

    /// The same token, receipt and wrapper addresses on every chain, each
    /// chain binding its own beacons, timelock and authorisers.
    function testRunBase() external {
        checkRunOnChain(LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testRunEthereum() external {
        checkRunOnChain(LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testRunHyperEvm() external {
        checkRunOnChain(LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testRunRobinhood() external {
        checkRunOnChain(LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testRunBsc() external {
        checkRunOnChain(LibSafeInvariants.BSC_CHAIN_ID);
    }

    /// A second run builds nothing and passes its checks.
    function testRerunIsANoOp() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        script.run();
        vm.recordLogs();
        script.run();
        assertEq(vm.getRecordedLogs().length, 0, "rerun built something");
        assertRegionLanded(Region.US, "US Test ST0x", "tUSTEST");
    }

    /// A token someone else built from the same bindings is the pinned token,
    /// and the run completes around it.
    function testRunAdoptsATokenAnotherCallerBuilt() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        vm.prank(makeAddr("anyone"));
        address token = factory()
            .registryBeaconProxy(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME,
                LibStoxTestTokens.vaultData(Region.EU),
                bytes32(0)
            );
        assertEq(token, LibStoxTestTokens.EU_TOKEN);
        script.run();
        assertRegionLanded(Region.EU, "EU Test ST0x", "tEUTEST");
    }

    function testPreflightRefusesMissingFactory() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        address target = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        vm.etch(target, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyNotDeployed.selector,
                target,
                LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH,
                target.codehash
            )
        );
        script.preflight();
    }

    function testPreflightRefusesMissingRegistry() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        address target = LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS;
        vm.etch(target, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyNotDeployed.selector,
                target,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                target.codehash
            )
        );
        script.preflight();
    }

    function checkBeaconBindingRefused(bytes32 name, uint256 index) internal {
        setUpChain(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        address other = address(new UpgradeableBeacon(LibProdDeployCurrent.STOX_RECEIPT_VAULT, address(this)));
        LibTestDeploy.bind(vm, LibStoxConfig.ROOT_AUTHORITY, name, abi.encode(other));
        address expected = LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[index];
        vm.expectRevert(abi.encodeWithSelector(BeaconBindingMismatch.selector, name, expected, other));
        script.preflight();
    }

    function testPreflightRefusesVaultBeaconOffProd() external {
        checkBeaconBindingRefused(LibStoxConfig.VAULT_BEACON_NAME, LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX);
    }

    function testPreflightRefusesReceiptBeaconOffProd() external {
        checkBeaconBindingRefused(LibStoxConfig.RECEIPT_BEACON_NAME, LibBeaconInvariants.RECEIPT_BEACON_INDEX);
    }

    function testPreflightRefusesWrapperBeaconOffProd() external {
        checkBeaconBindingRefused(
            LibStoxConfig.WRAPPER_BEACON_NAME, LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX
        );
    }

    function checkBeaconImplementationRefused(uint256 index, address expected) internal {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        address beacon = LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[index];
        address stale = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1;
        vm.etch(stale, hex"00");
        vm.prank(LibTimelockInvariants.timelockForChainId(block.chainid));
        UpgradeableBeacon(beacon).upgradeTo(stale);
        vm.expectRevert(abi.encodeWithSelector(BeaconImplementationMismatch.selector, beacon, expected, stale));
        script.preflight();
    }

    /// Before the token beacon upgrade, the vault beacon serves another
    /// implementation and the run waits.
    function testPreflightRefusesVaultBeaconNotUpgraded() external {
        checkBeaconImplementationRefused(
            LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX, LibProdDeployCurrent.STOX_RECEIPT_VAULT
        );
    }

    function testPreflightRefusesReceiptBeaconNotUpgraded() external {
        checkBeaconImplementationRefused(LibBeaconInvariants.RECEIPT_BEACON_INDEX, LibProdDeployCurrent.STOX_RECEIPT);
    }

    function testPreflightRefusesUnboundUsRbac() external {
        setUpChainWithoutRbac(LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.US_RBAC_NAME
            )
        );
        script.preflight();
    }

    function testPreflightRefusesUnboundEuRbac() external {
        setUpChainWithoutRbac(LibSafeInvariants.BASE_CHAIN_ID);
        bindRbac(
            LibStoxConfig.US_RBAC_NAME,
            LibTimelockInvariants.timelockForChainId(block.chainid),
            LibAuthoriserInvariants.authoriserForChainId(block.chainid)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.EU_RBAC_NAME
            )
        );
        script.preflight();
    }

    function testPreflightRefusesRbacOwnedOffTheTimelock() external {
        setUpChain(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bindRbac(LibStoxConfig.US_RBAC_NAME, safe, LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        vm.expectRevert(
            abi.encodeWithSelector(
                RbacOwnerMismatch.selector, Region.US, LibTimelockInvariants.timelockForChainId(block.chainid), safe
            )
        );
        script.preflight();
    }

    /// The EU RBAC on the US authoriser, which would let every US-fleet
    /// depositor mint EU tokens.
    function testPreflightRefusesEuRbacOnTheUsAuthoriser() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        address us = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        bindRbac(LibStoxConfig.EU_RBAC_NAME, LibTimelockInvariants.timelockForChainId(block.chainid), us);
        vm.expectRevert(
            abi.encodeWithSelector(
                RbacAuthoriserMismatch.selector,
                Region.EU,
                LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
                us
            )
        );
        script.preflight();
    }

    function testPreflightRefusesUsRbacOnTheEuAuthoriser() external {
        setUpChain(LibSafeInvariants.BSC_CHAIN_ID);
        address eu = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        bindRbac(LibStoxConfig.US_RBAC_NAME, LibTimelockInvariants.timelockForChainId(block.chainid), eu);
        vm.expectRevert(
            abi.encodeWithSelector(
                RbacAuthoriserMismatch.selector,
                Region.US,
                LibAuthoriserInvariants.authoriserForChainId(block.chainid),
                eu
            )
        );
        script.preflight();
    }

    function testLandedRefusesUnbuiltToken() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(TestTokenNotLanded.selector, Region.US, LibStoxTestTokens.US_TOKEN));
        script.assertLanded(Region.US);
    }

    function testLandedRefusesUnbuiltWrapper() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        factory()
            .registryBeaconProxy(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME,
                LibStoxTestTokens.vaultData(Region.US),
                bytes32(0)
            );
        vm.expectRevert(abi.encodeWithSelector(TestTokenNotLanded.selector, Region.US, LibStoxTestTokens.US_WRAPPER));
        script.assertLanded(Region.US);
    }

    function testLandedRefusesOffPinReceipt() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        script.run();
        vm.mockCall(
            LibStoxTestTokens.EU_TOKEN, abi.encodeCall(IReceiptVaultV3.receipt, ()), abi.encode(makeAddr("other"))
        );
        vm.expectRevert(abi.encodeWithSelector(TestTokenNotLanded.selector, Region.EU, LibStoxTestTokens.EU_RECEIPT));
        script.assertLanded(Region.EU);
    }

    function testLandedRefusesWrapperOfAnotherAsset() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        script.run();
        vm.mockCall(LibStoxTestTokens.US_WRAPPER, abi.encodeCall(IERC4626.asset, ()), abi.encode(makeAddr("other")));
        vm.expectRevert(abi.encodeWithSelector(TestTokenNotLanded.selector, Region.US, LibStoxTestTokens.US_WRAPPER));
        script.assertLanded(Region.US);
    }

    function testLandedRefusesTokenOffTheTimelock() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        script.run();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address other = makeAddr("other-owner");
        vm.prank(timelock);
        Ownable(LibStoxTestTokens.EU_TOKEN).transferOwnership(other);
        vm.expectRevert(abi.encodeWithSelector(TestTokenOwnerMismatch.selector, Region.EU, timelock, other));
        script.assertLanded(Region.EU);
    }

    function testLandedRefusesTokenOffItsRegionsAuthoriser() external {
        setUpChain(LibSafeInvariants.BASE_CHAIN_ID);
        script.run();
        address eu = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        vm.mockCall(LibStoxTestTokens.US_TOKEN, abi.encodeCall(IAuthorizableV1.authorizer, ()), abi.encode(eu));
        vm.expectRevert(
            abi.encodeWithSelector(
                TestTokenAuthoriserMismatch.selector,
                Region.US,
                LibAuthoriserInvariants.authoriserForChainId(block.chainid),
                eu
            )
        );
        script.assertLanded(Region.US);
    }
}
