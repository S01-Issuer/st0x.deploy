// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {IAuthorizeV1} from "rain-vats-0.2.18/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.18/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    VaultBeaconMismatch,
    ReceiptBeaconMismatch,
    RbacOwnerMismatch,
    RbacAuthorizerMismatch,
    WrapperBeaconMismatch
} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "../../src/lib/LibProdTokenTargets.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployTokenBindingsTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function bindAddress(bytes32 name, address value) internal {
        LibTestDeploy.bind(vm, LibRegistryAuthority.ROOT_AUTHORITY, name, "address", abi.encode(value));
    }

    function bindRbac(bytes32 name, address owner, address authorizer) internal {
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: IAuthorizeV1(authorizer)}))
        );
    }

    function bindPinnedBeacons() internal {
        bindAddress(LibStoxConfig.VAULT_BEACON_NAME, LibProdTokenTargets.vaultBeacon());
        bindAddress(LibStoxConfig.RECEIPT_BEACON_NAME, LibProdDeployCurrent.STOX_RECEIPT_BEACON);
    }

    function bindPinned(uint256 chainId) internal {
        bindPinnedBeacons();
        bindRbac(
            LibStoxConfig.RBAC_US_NAME,
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            LibAuthoriserInvariants.authoriserForChainId(chainId)
        );
        bindRbac(
            LibStoxConfig.RBAC_EU_NAME,
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            LibAuthoriserInvariants.euAuthoriserForChainId(chainId)
        );
    }

    function rbacName(Region region) internal pure returns (bytes32) {
        return region == Region.US ? LibStoxConfig.RBAC_US_NAME : LibStoxConfig.RBAC_EU_NAME;
    }

    function pinnedAuthorizer(Region region, uint256 chainId) internal pure returns (address) {
        return region == Region.US
            ? LibAuthoriserInvariants.authoriserForChainId(chainId)
            : LibAuthoriserInvariants.euAuthoriserForChainId(chainId);
    }

    function productionAndTestTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        TokenConfig[] memory configs = new TokenConfig[](production.length + test.length);
        for (uint256 i = 0; i < production.length; i++) {
            configs[i] = production[i];
        }
        for (uint256 i = 0; i < test.length; i++) {
            configs[production.length + i] = test[i];
        }
        return configs;
    }

    function testTokensRefuseUnboundVaultBeacon() external {
        TokenConfig[] memory configs = productionAndTestTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConfigRegistryV5.NameNotRegistered.selector,
                        LibRegistryAuthority.ROOT_AUTHORITY,
                        LibStoxConfig.VAULT_BEACON_NAME
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensRefuseUnboundReceiptBeacon() external {
        TokenConfig[] memory configs = productionAndTestTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindAddress(LibStoxConfig.VAULT_BEACON_NAME, LibProdTokenTargets.vaultBeacon());
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConfigRegistryV5.NameNotRegistered.selector,
                        LibRegistryAuthority.ROOT_AUTHORITY,
                        LibStoxConfig.RECEIPT_BEACON_NAME
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensRefuseUnboundRegionRbac() external {
        TokenConfig[] memory configs = productionAndTestTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindPinnedBeacons();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConfigRegistryV5.NameNotRegistered.selector,
                        LibRegistryAuthority.ROOT_AUTHORITY,
                        rbacName(configs[j].region)
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    /// One production token per region, then every test token.
    function oneRowPerRegion(uint256 usSeed, uint256 euSeed) internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        uint256 usCount = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].region == Region.US) {
                usCount++;
            }
        }
        uint256 usPick = bound(usSeed, 0, usCount - 1);
        uint256 euPick = bound(euSeed, 0, configs.length - usCount - 1);
        TokenConfig[] memory sample = new TokenConfig[](2 + test.length);
        uint256 usSeen = 0;
        uint256 euSeen = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].region == Region.US) {
                if (usSeen++ == usPick) {
                    sample[0] = configs[i];
                }
            } else if (euSeen++ == euPick) {
                sample[1] = configs[i];
            }
        }
        for (uint256 i = 0; i < test.length; i++) {
            sample[2 + i] = test[i];
        }
        return sample;
    }

    function testTokensRefuseOtherVaultBeacon(address wrong, uint256 usSeed, uint256 euSeed) external {
        vm.assume(wrong != LibProdTokenTargets.vaultBeacon());
        DeploySuite[] memory tokens = harness.declaredTokenSuites(oneRowPerRegion(usSeed, euSeed));
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            bindAddress(LibStoxConfig.VAULT_BEACON_NAME, wrong);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(VaultBeaconMismatch.selector, wrong, LibProdTokenTargets.vaultBeacon())
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensRefuseOtherReceiptBeacon(address wrong, uint256 usSeed, uint256 euSeed) external {
        vm.assume(wrong != LibProdDeployCurrent.STOX_RECEIPT_BEACON);
        DeploySuite[] memory tokens = harness.declaredTokenSuites(oneRowPerRegion(usSeed, euSeed));
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            bindAddress(LibStoxConfig.RECEIPT_BEACON_NAME, wrong);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        ReceiptBeaconMismatch.selector, wrong, LibProdDeployCurrent.STOX_RECEIPT_BEACON
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensRefuseOtherRbacOwner(address owner, uint256 usSeed, uint256 euSeed) external {
        vm.assume(owner != LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        TokenConfig[] memory configs = oneRowPerRegion(usSeed, euSeed);
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.chainId(chainId);
            bindPinnedBeacons();
            bindRbac(LibStoxConfig.RBAC_US_NAME, owner, pinnedAuthorizer(Region.US, chainId));
            bindRbac(LibStoxConfig.RBAC_EU_NAME, owner, pinnedAuthorizer(Region.EU, chainId));
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        RbacOwnerMismatch.selector,
                        rbacName(configs[j].region),
                        owner,
                        LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensRefuseOtherRbacAuthorizer(address authorizer, uint256 usSeed, uint256 euSeed) external {
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.assume(authorizer != pinnedAuthorizer(Region.US, networks[i].chainId));
            vm.assume(authorizer != pinnedAuthorizer(Region.EU, networks[i].chainId));
        }
        TokenConfig[] memory configs = oneRowPerRegion(usSeed, euSeed);
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.chainId(chainId);
            bindPinnedBeacons();
            bindRbac(LibStoxConfig.RBAC_US_NAME, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, authorizer);
            bindRbac(LibStoxConfig.RBAC_EU_NAME, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, authorizer);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        RbacAuthorizerMismatch.selector,
                        rbacName(configs[j].region),
                        authorizer,
                        pinnedAuthorizer(configs[j].region, chainId)
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensRefuseOtherRegionAuthoriser() external {
        TokenConfig[] memory configs = productionAndTestTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.chainId(chainId);
            bindPinnedBeacons();
            bindRbac(
                LibStoxConfig.RBAC_US_NAME,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                pinnedAuthorizer(Region.EU, chainId)
            );
            bindRbac(
                LibStoxConfig.RBAC_EU_NAME,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                pinnedAuthorizer(Region.US, chainId)
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                Region region = configs[j].region;
                Region other = region == Region.US ? Region.EU : Region.US;
                vm.expectRevert(
                    abi.encodeWithSelector(
                        RbacAuthorizerMismatch.selector,
                        rbacName(region),
                        pinnedAuthorizer(other, chainId),
                        pinnedAuthorizer(region, chainId)
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensIgnoreOtherRegionRbac() external {
        TokenConfig[] memory configs = productionAndTestTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.chainId(chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                bindPinned(chainId);
                Region other = configs[j].region == Region.US ? Region.EU : Region.US;
                bindRbac(rbacName(other), address(0), address(0));
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function testTokensAcceptPinnedBindings() external {
        TokenConfig[] memory configs = productionAndTestTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    function declaredTestTokenWrappers() internal view returns (DeploySuite[] memory) {
        DeploySuite[] memory wrappers = new DeploySuite[](2);
        wrappers[0] = harness.declaredSuite("stox-token-tustest-wrapper");
        wrappers[1] = harness.declaredSuite("stox-token-teutest-wrapper");
        return wrappers;
    }

    function testTestTokenWrappersRefuseUnboundWrapperBeacon() external {
        DeploySuite[] memory wrappers = declaredTestTokenWrappers();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            for (uint256 j = 0; j < wrappers.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IConfigRegistryV5.NameNotRegistered.selector,
                        LibRegistryAuthority.ROOT_AUTHORITY,
                        LibStoxConfig.WRAPPER_BEACON_NAME
                    )
                );
                harness.exposedPreDeployCheck(wrappers[j], networks[i]);
            }
        }
    }

    function testTestTokenWrappersRefuseOtherWrapperBeacon(address wrong) external {
        vm.assume(wrong != LibProdTokenTargets.wrapperBeacon());
        DeploySuite[] memory wrappers = declaredTestTokenWrappers();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            bindAddress(LibStoxConfig.WRAPPER_BEACON_NAME, wrong);
            for (uint256 j = 0; j < wrappers.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(WrapperBeaconMismatch.selector, wrong, LibProdTokenTargets.wrapperBeacon())
                );
                harness.exposedPreDeployCheck(wrappers[j], networks[i]);
            }
        }
    }

    /// The wrapper beacon is the only binding a wrapper reads, so the token bindings stay unbound.
    function testTestTokenWrappersAcceptPinnedWrapperBeacon() external {
        DeploySuite[] memory wrappers = declaredTestTokenWrappers();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindAddress(LibStoxConfig.WRAPPER_BEACON_NAME, LibProdTokenTargets.wrapperBeacon());
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < wrappers.length; j++) {
                harness.exposedPreDeployCheck(wrappers[j], networks[i]);
            }
        }
    }
}
