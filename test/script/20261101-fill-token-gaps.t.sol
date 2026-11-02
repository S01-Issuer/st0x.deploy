// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.29/src/interface/IConfigRegistryV5.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE
} from "rain-deploy-0.1.29/src/generated/0_1_29/ConfigRegistry.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V8_ADDRESS,
    CREATION_CODE as CLONE_FACTORY_V8_CREATION_CODE
} from "rain-factory-deploy-0.2.5/src/generated/0_2_5/CloneFactory.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.5/src/concrete/CloneFactory.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.9/src/interface/ICloneableFactoryV7.sol";
import {LibRainDeployRegistryBeaconProxy} from "rain-factory-0.2.9/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.16/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.16/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.16/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {FillTokenGaps} from "../../script/20261101-fill-token-gaps.s.sol";
import {StoxCorporateActionsFacet} from "../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4 as V4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxTokenProxy} from "../../src/generated/LibStoxTokenProxy.sol";
import {IST0xVaultBeaconSet} from "../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";

/// @title FillTokenGapsTest
/// @notice `FillTokenGaps.run()` lands exactly the production token rows a network is missing, and `check()` refuses
/// a network that is missing any row or any declared dependency.
/// @dev The script forks `NETWORK` per row, so every account it reads is persistent: the fork supplies only the chain.
contract FillTokenGapsTest is Test {
    address internal constant US_OWNER = address(uint160(uint256(keccak256("st0x.test.fill-token-gaps.us-owner"))));
    address internal constant EU_OWNER = address(uint160(uint256(keccak256("st0x.test.fill-token-gaps.eu-owner"))));

    FillTokenGaps internal sScript;
    address internal sVaultBeacon;
    address internal sReceiptBeacon;
    IAuthorizeV1 internal sUsAuthorizer;
    IAuthorizeV1 internal sEuAuthorizer;
    address[] internal sTokens;
    address[] internal sReceipts;

    function setUp() external {
        vm.setEnv("NETWORK", LibRainDeploy.BASE);

        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_CREATION_CODE_0_1_1);
        LibRainDeploy.deployZoltu(V4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1);
        IST0xVaultBeaconSet set = IST0xVaultBeaconSet(
            LibRainDeploy.deployZoltu(V4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1)
        );
        sVaultBeacon = address(set.iOffchainAssetReceiptVaultBeacon());
        sReceiptBeacon = address(set.iReceiptBeacon());
        LibTestDeploy.deployImplementations(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        upgrade(sReceiptBeacon, V4.STOX_RECEIPT_CANDIDATE);
        upgrade(sVaultBeacon, V4.STOX_RECEIPT_VAULT_CANDIDATE);
        assertEq(LibRainDeploy.deployZoltu(CLONE_FACTORY_V8_CREATION_CODE), CLONE_FACTORY_V8_ADDRESS, "factory");
        assertEq(LibRainDeploy.deployZoltu(CONFIG_REGISTRY_CREATION_CODE), CONFIG_REGISTRY_ADDRESS, "registry");

        StoxOffchainAssetReceiptVaultAuthorizerV1 authorizerImplementation =
            new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory authorizerFactory = new CloneFactory();
        sUsAuthorizer = newAuthorizer(authorizerFactory, authorizerImplementation, US_OWNER);
        sEuAuthorizer = newAuthorizer(authorizerFactory, authorizerImplementation, EU_OWNER);

        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            address token = ICloneableFactoryV7(CLONE_FACTORY_V8_ADDRESS)
                .predictRegistryBeaconProxyAddress(
                    CONFIG_REGISTRY_ADDRESS,
                    LibStoxConfig.ROOT_AUTHORITY,
                    LibStoxConfig.VAULT_BEACON_NAME,
                    tokenData(configs[i]),
                    keccak256(bytes(configs[i].underlying))
                );
            sTokens.push(token);
            sReceipts.push(
                ICloneableFactoryV7(CLONE_FACTORY_V8_ADDRESS)
                    .predictRegistryBeaconProxyAddress(
                        CONFIG_REGISTRY_ADDRESS,
                        LibStoxConfig.ROOT_AUTHORITY,
                        LibStoxConfig.RECEIPT_BEACON_NAME,
                        abi.encode(token),
                        bytes32(0)
                    )
            );
        }

        sScript = new FillTokenGaps();

        address[] memory persistent = new address[](11 + 2 * configs.length);
        persistent[0] = CLONE_FACTORY_V8_ADDRESS;
        persistent[1] = CONFIG_REGISTRY_ADDRESS;
        persistent[2] = sVaultBeacon;
        persistent[3] = sReceiptBeacon;
        persistent[4] = V4.STOX_RECEIPT_CANDIDATE;
        persistent[5] = V4.STOX_RECEIPT_VAULT_CANDIDATE;
        persistent[6] = facet;
        persistent[7] = address(authorizerImplementation);
        persistent[8] = address(sUsAuthorizer);
        persistent[9] = address(sEuAuthorizer);
        persistent[10] = address(sScript);
        for (uint256 i = 0; i < configs.length; i++) {
            vm.deal(sTokens[i], 0);
            vm.deal(sReceipts[i], 0);
            persistent[11 + 2 * i] = sTokens[i];
            persistent[12 + 2 * i] = sReceipts[i];
        }
        vm.makePersistent(persistent);
    }

    function upgrade(address beacon, address implementation) internal {
        vm.prank(UpgradeableBeacon(beacon).owner());
        UpgradeableBeacon(beacon).upgradeTo(implementation);
    }

    function newAuthorizer(
        CloneFactory factory,
        StoxOffchainAssetReceiptVaultAuthorizerV1 implementation,
        address admin
    ) internal returns (IAuthorizeV1) {
        return IAuthorizeV1(
            factory.cloneDeterministic(
                address(implementation),
                abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})),
                bytes32(uint256(uint160(admin)))
            )
        );
    }

    function rbacName(Region region) internal pure returns (bytes32) {
        return region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME;
    }

    function tokenData(TokenConfig memory config) internal pure returns (bytes memory) {
        return
            LibTestDeploy.vaultData(config.name, config.symbol, LibStoxConfig.ROOT_AUTHORITY, rbacName(config.region));
    }

    function bindBeacon(bytes32 name, address beacon) internal {
        LibTestDeploy.bind(vm, LibStoxConfig.ROOT_AUTHORITY, name, "address", abi.encode(beacon));
    }

    function bindRbac(bytes32 name, address owner, IAuthorizeV1 authorizer) internal {
        LibTestDeploy.bind(
            vm,
            LibStoxConfig.ROOT_AUTHORITY,
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: authorizer}))
        );
    }

    function bindRoot() internal {
        bindBeacon(LibStoxConfig.VAULT_BEACON_NAME, sVaultBeacon);
        bindBeacon(LibStoxConfig.RECEIPT_BEACON_NAME, sReceiptBeacon);
        bindRbac(LibStoxConfig.RBAC_US_NAME, US_OWNER, sUsAuthorizer);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, sEuAuthorizer);
    }

    function deployRow(uint256 i) internal {
        TokenConfig memory config = LibProdTokenConfig.productionTokenConfigs()[i];
        ICloneableFactoryV7(CLONE_FACTORY_V8_ADDRESS)
            .registryBeaconProxy(
                CONFIG_REGISTRY_ADDRESS,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME,
                tokenData(config),
                keccak256(bytes(config.underlying))
            );
    }

    function deployEveryRow() internal {
        for (uint256 i = 0; i < sTokens.length; i++) {
            deployRow(i);
        }
    }

    function tokenDeployCall(uint256 i) internal pure returns (bytes memory) {
        TokenConfig memory config = LibProdTokenConfig.productionTokenConfigs()[i];
        return abi.encodeCall(
            ICloneableFactoryV7.registryBeaconProxy,
            (
                CONFIG_REGISTRY_ADDRESS,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME,
                tokenData(config),
                keccak256(bytes(config.underlying))
            )
        );
    }

    function firstRowOf(Region region) internal pure returns (uint256) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].region == region) return i;
        }
        revert("no row in region");
    }

    function assertEveryRowIsItsToken() internal view {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertEq(sTokens.length, configs.length, "rows");
        for (uint256 i = 0; i < configs.length; i++) {
            assertEq(sTokens[i].code, LibStoxTokenProxy.RUNTIME_CODE, configs[i].underlying);
            StoxReceiptVault token = StoxReceiptVault(payable(sTokens[i]));
            bool us = configs[i].region == Region.US;
            assertEq(token.name(), configs[i].name, configs[i].underlying);
            assertEq(token.symbol(), configs[i].symbol, configs[i].underlying);
            assertEq(token.owner(), us ? US_OWNER : EU_OWNER, configs[i].underlying);
            assertEq(address(token.authorizer()), address(us ? sUsAuthorizer : sEuAuthorizer), configs[i].underlying);
            assertEq(address(token.receipt()), sReceipts[i], configs[i].underlying);
            assertGt(sReceipts[i].code.length, 0, configs[i].underlying);
        }
    }

    function changeDependency(address dependency, bytes memory code) internal returns (bytes memory) {
        bytes memory refusal = abi.encodeWithSelector(
            LibRainDeploy.DependencyChanged.selector,
            LibRainDeploy.BASE,
            dependency,
            dependency.codehash,
            keccak256(code)
        );
        vm.etch(dependency, code);
        return refusal;
    }

    function testDeclaresItselfNotAMigration() external view {
        assertEq(abi.encode(sScript.declaration()), abi.encode(LibStoxMigrations.notAMigration()));
    }

    function testRunLandsEveryRowAtItsAddressAsItsToken() external {
        bindRoot();
        for (uint256 i = 0; i < sTokens.length; i++) {
            assertEq(sTokens[i].code.length, 0, "missing before");
        }
        sScript.run();
        assertEq(block.chainid, LibSafeInvariants.BASE_CHAIN_ID, "network");
        assertEveryRowIsItsToken();
    }

    function testRunDeploysEachRowOnceAsTheCaller() external {
        bindRoot();
        vm.recordLogs();
        sScript.run();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 deployed = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != CLONE_FACTORY_V8_ADDRESS) continue;
            if (logs[i].topics[0] != ICloneableFactoryV7.NewRegistryBeaconProxy.selector) continue;
            (address sender,,, bytes32 beaconName,, address proxy,,) =
                abi.decode(logs[i].data, (address, address, address, bytes32, address, address, bytes32, bytes));
            if (beaconName != LibStoxConfig.VAULT_BEACON_NAME) continue;
            assertEq(sender, address(this), "sender");
            assertEq(proxy, sTokens[deployed], "row order");
            deployed++;
        }
        assertEq(deployed, sTokens.length, "one deploy per row");
    }

    function testSecondRunDeploysNothing() external {
        bindRoot();
        sScript.run();
        vm.expectCall(CLONE_FACTORY_V8_ADDRESS, abi.encodePacked(ICloneableFactoryV7.registryBeaconProxy.selector), 0);
        sScript.run();
        assertEveryRowIsItsToken();
    }

    function testRunOnAPartlyFilledNetworkDeploysOnlyTheMissingRows() external {
        bindRoot();
        for (uint256 i = 0; i < sTokens.length; i += 3) {
            deployRow(i);
        }
        for (uint256 i = 0; i < sTokens.length; i++) {
            vm.expectCall(CLONE_FACTORY_V8_ADDRESS, tokenDeployCall(i), i % 3 == 0 ? 0 : 1);
        }
        sScript.run();
        assertEveryRowIsItsToken();
    }

    function testRunRefusesForeignCodeAtARowsAddress() external {
        bindRoot();
        bytes memory foreign = CONFIG_REGISTRY_ADDRESS.code;
        vm.etch(sTokens[1], foreign);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.BASE,
                sTokens[1],
                keccak256(LibStoxTokenProxy.RUNTIME_CODE),
                keccak256(foreign)
            )
        );
        sScript.run();
    }

    function testRunRefusesWithoutTheCloneFactory() external {
        bindRoot();
        vm.etch(CLONE_FACTORY_V8_ADDRESS, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.BASE, CLONE_FACTORY_V8_ADDRESS
            )
        );
        sScript.run();
    }

    function testRunRefusesAChangedCloneFactory() external {
        bindRoot();
        bytes memory foreign = CONFIG_REGISTRY_ADDRESS.code;
        vm.expectRevert(changeDependency(CLONE_FACTORY_V8_ADDRESS, foreign));
        sScript.run();
    }

    function testRunRefusesWithoutTheConfigRegistry() external {
        bindRoot();
        vm.etch(CONFIG_REGISTRY_ADDRESS, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.BASE, CONFIG_REGISTRY_ADDRESS
            )
        );
        sScript.run();
    }

    function testRunRefusesAChangedConfigRegistry() external {
        bindRoot();
        bytes memory foreign = CLONE_FACTORY_V8_ADDRESS.code;
        vm.expectRevert(changeDependency(CONFIG_REGISTRY_ADDRESS, foreign));
        sScript.run();
    }

    function testRunRefusesWithoutTheVaultBeacon() external {
        bindRoot();
        vm.etch(sVaultBeacon, "");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.BASE, sVaultBeacon)
        );
        sScript.run();
    }

    function testRunRefusesAChangedVaultBeacon() external {
        bindRoot();
        bytes memory foreign = CLONE_FACTORY_V8_ADDRESS.code;
        vm.expectRevert(changeDependency(sVaultBeacon, foreign));
        sScript.run();
    }

    function testRunChecksDependenciesWhenEveryRowExists() external {
        bindRoot();
        deployEveryRow();
        bytes memory foreign = CONFIG_REGISTRY_ADDRESS.code;
        vm.expectRevert(changeDependency(CLONE_FACTORY_V8_ADDRESS, foreign));
        sScript.run();
    }

    function testRunRefusesAnUnboundVaultBeacon() external {
        bindBeacon(LibStoxConfig.RECEIPT_BEACON_NAME, sReceiptBeacon);
        bindRbac(LibStoxConfig.RBAC_US_NAME, US_OWNER, sUsAuthorizer);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, sEuAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME
            )
        );
        sScript.run();
    }

    function testRunRefusesAVaultBeaconBoundElsewhere() external {
        bindBeacon(LibStoxConfig.VAULT_BEACON_NAME, sReceiptBeacon);
        bindBeacon(LibStoxConfig.RECEIPT_BEACON_NAME, sReceiptBeacon);
        bindRbac(LibStoxConfig.RBAC_US_NAME, US_OWNER, sUsAuthorizer);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, sEuAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployRegistryBeaconProxy.RegistryBeaconProxyBeaconMismatch.selector,
                LibRainDeploy.BASE,
                sVaultBeacon,
                sReceiptBeacon
            )
        );
        sScript.run();
    }

    function testRunRefusesAnUnboundReceiptBeacon() external {
        bindBeacon(LibStoxConfig.VAULT_BEACON_NAME, sVaultBeacon);
        bindRbac(LibStoxConfig.RBAC_US_NAME, US_OWNER, sUsAuthorizer);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, sEuAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.RECEIPT_BEACON_NAME
            )
        );
        sScript.run();
    }

    function testRunRefusesAnUnboundUsRbac() external {
        bindBeacon(LibStoxConfig.VAULT_BEACON_NAME, sVaultBeacon);
        bindBeacon(LibStoxConfig.RECEIPT_BEACON_NAME, sReceiptBeacon);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, sEuAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.RBAC_US_NAME
            )
        );
        sScript.run();
    }

    function testRunRefusesAnUnboundEuRbac() external {
        bindBeacon(LibStoxConfig.VAULT_BEACON_NAME, sVaultBeacon);
        bindBeacon(LibStoxConfig.RECEIPT_BEACON_NAME, sReceiptBeacon);
        bindRbac(LibStoxConfig.RBAC_US_NAME, US_OWNER, sUsAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.RBAC_EU_NAME
            )
        );
        sScript.run();
    }

    function testRunRefusesSeatingTheCallerAsATokenOwner() external {
        bindBeacon(LibStoxConfig.VAULT_BEACON_NAME, sVaultBeacon);
        bindBeacon(LibStoxConfig.RECEIPT_BEACON_NAME, sReceiptBeacon);
        bindRbac(LibStoxConfig.RBAC_US_NAME, address(this), sUsAuthorizer);
        bindRbac(LibStoxConfig.RBAC_EU_NAME, EU_OWNER, sEuAuthorizer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployRegistryBeaconProxy.RegistryBeaconProxySeatsDeployKey.selector,
                LibRainDeploy.BASE,
                sTokens[firstRowOf(Region.US)]
            )
        );
        sScript.run();
    }

    function testCheckPassesAfterRun() external {
        bindRoot();
        sScript.run();
        sScript.check();
    }

    function testCheckPassesWhenEveryRowWasDeployedWithoutTheScript() external {
        bindRoot();
        deployEveryRow();
        sScript.check();
    }

    function testCheckRefusesANetworkWithNoTokens() external {
        bindRoot();
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, sTokens[0])
        );
        sScript.check();
    }

    function testCheckRefusesAMissingRow() external {
        bindRoot();
        uint256 missing = sTokens.length / 2;
        for (uint256 i = 0; i < sTokens.length; i++) {
            if (i != missing) deployRow(i);
        }
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, sTokens[missing])
        );
        sScript.check();
    }

    function testCheckRefusesForeignCodeAtARowsAddress() external {
        bindRoot();
        deployEveryRow();
        uint256 row = sTokens.length - 1;
        bytes memory foreign = sReceipts[row].code;
        vm.etch(sTokens[row], foreign);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.BASE,
                sTokens[row],
                keccak256(LibStoxTokenProxy.RUNTIME_CODE),
                keccak256(foreign)
            )
        );
        sScript.check();
    }

    function testCheckRefusesWithoutTheCloneFactory() external {
        bindRoot();
        deployEveryRow();
        vm.etch(CLONE_FACTORY_V8_ADDRESS, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.BASE, CLONE_FACTORY_V8_ADDRESS
            )
        );
        sScript.check();
    }

    function testCheckRefusesAChangedCloneFactory() external {
        bindRoot();
        deployEveryRow();
        bytes memory foreign = CONFIG_REGISTRY_ADDRESS.code;
        vm.expectRevert(changeDependency(CLONE_FACTORY_V8_ADDRESS, foreign));
        sScript.check();
    }

    function testCheckRefusesWithoutTheConfigRegistry() external {
        bindRoot();
        deployEveryRow();
        vm.etch(CONFIG_REGISTRY_ADDRESS, "");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.BASE, CONFIG_REGISTRY_ADDRESS
            )
        );
        sScript.check();
    }

    function testCheckRefusesAChangedConfigRegistry() external {
        bindRoot();
        deployEveryRow();
        bytes memory foreign = CLONE_FACTORY_V8_ADDRESS.code;
        vm.expectRevert(changeDependency(CONFIG_REGISTRY_ADDRESS, foreign));
        sScript.check();
    }

    function testCheckRefusesWithoutTheVaultBeacon() external {
        bindRoot();
        deployEveryRow();
        vm.etch(sVaultBeacon, "");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.BASE, sVaultBeacon)
        );
        sScript.check();
    }

    function testCheckRefusesAChangedVaultBeacon() external {
        bindRoot();
        deployEveryRow();
        bytes memory foreign = CLONE_FACTORY_V8_ADDRESS.code;
        vm.expectRevert(changeDependency(sVaultBeacon, foreign));
        sScript.check();
    }
}
