// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.20/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {
    VaultBeaconMismatch,
    ReceiptBeaconMismatch,
    RbacOwnerMismatch,
    RbacAuthorizerMismatch,
    WrapperBeaconMismatch,
    VaultBeaconNotDeployed
} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenParams} from "../../src/lib/LibProdTokenParams.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {BeaconImplementationMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {LibTestTokenRows} from "../lib/LibTestTokenRows.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployTokenBindingsTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
        placeVaultBeacon(LibProdDeployCurrent.STOX_RECEIPT_VAULT);
    }

    /// Deploys the governance timelock with `proposer` as its proposer.
    function deployTimelock(address proposer) internal {
        LibTestBeaconInitialOwnerBind.deployTimelock(vm, proposer);
    }

    /// The pinned vault beacon, serving `implementation`.
    function placeVaultBeacon(address implementation) internal {
        if (implementation.code.length == 0) {
            vm.etch(implementation, hex"00");
        }
        LibTestDeploy.placeBeacon(vm, LibProdTokenParams.vaultBeacon(), implementation, address(this));
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
        bindAddress(LibStoxConfig.VAULT_BEACON_NAME, LibProdTokenParams.vaultBeacon());
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

    function testTokensRefuseUnboundVaultBeacon() external {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
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
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindAddress(LibStoxConfig.VAULT_BEACON_NAME, LibProdTokenParams.vaultBeacon());
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
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
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

    function oneRowPerRegion(uint256 usSeed, uint256 euSeed) internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        uint256 usCount = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].region == Region.US) {
                usCount++;
            }
        }
        uint256 usPick = bound(usSeed, 0, usCount - 1);
        uint256 euPick = bound(euSeed, 0, configs.length - usCount - 1);
        TokenConfig[] memory sample = new TokenConfig[](2);
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
        return sample;
    }

    function testTokensRefuseOtherVaultBeacon(address wrong, uint256 usSeed, uint256 euSeed) external {
        vm.assume(wrong != LibProdTokenParams.vaultBeacon());
        DeploySuite[] memory tokens = harness.declaredTokenSuites(oneRowPerRegion(usSeed, euSeed));
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            bindAddress(LibStoxConfig.VAULT_BEACON_NAME, wrong);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(VaultBeaconMismatch.selector, wrong, LibProdTokenParams.vaultBeacon())
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
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
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
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            uint256 chainId = networks[i].chainId;
            vm.chainId(chainId);
            deployTimelock(LibSafeInvariants.safeForChainId(chainId));
            for (uint256 j = 0; j < tokens.length; j++) {
                bindPinned(chainId);
                Region other = configs[j].region == Region.US ? Region.EU : Region.US;
                bindRbac(rbacName(other), address(0), address(0));
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
            vm.revertToState(snapshot);
        }
    }

    function testTokensAcceptPinnedBindings() external {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            deployTimelock(LibSafeInvariants.safeForChainId(networks[i].chainId));
            for (uint256 j = 0; j < tokens.length; j++) {
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
            vm.revertToState(snapshot);
        }
    }

    /// With every binding right but no timelock at its address, the tokens are refused.
    function testTokensRefuseAnUndeployedGovernanceTimelock() external {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        LibTimelockController.TimelockNotDeployed.selector,
                        LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    /// Other code at the governance timelock's address is refused, with its hash.
    function testTokensRefuseAGovernanceTimelockWithOtherCode() external {
        bytes memory code = hex"00";
        TokenConfig[] memory configs = LibProdTokenConfig.testTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        vm.chainId(networks[0].chainId);
        bindPinned(networks[0].chainId);
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, code);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockCodehashMismatch.selector,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK_CODEHASH,
                keccak256(code)
            )
        );
        harness.exposedPreDeployCheck(tokens[0], networks[0]);
    }

    /// A timelock with the pinned code but another proposer than the chain's Safe is refused.
    function testTokensRefuseAGovernanceTimelockWithAnotherProposer(address proposer) external {
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        address safe = LibSafeInvariants.safeForChainId(networks[0].chainId);
        vm.assume(proposer != safe && proposer != address(0));
        DeploySuite[] memory tokens = harness.declaredTokenSuites(LibProdTokenConfig.testTokenConfigs());
        vm.chainId(networks[0].chainId);
        bindPinned(networks[0].chainId);
        deployTimelock(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                safe
            )
        );
        harness.exposedPreDeployCheck(tokens[0], networks[0]);
    }

    /// The binding checks run first: with the timelock missing too, an unbound vault beacon is what the operator sees.
    function testTokensReportTheBindingBeforeTheTimelock() external {
        TokenConfig[] memory configs = LibProdTokenConfig.testTokenConfigs();
        DeploySuite[] memory tokens = harness.declaredTokenSuites(configs);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        vm.chainId(networks[0].chainId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME
            )
        );
        harness.exposedPreDeployCheck(tokens[0], networks[0]);
    }

    function testWrappersRefuseUnboundWrapperBeacon() external {
        DeploySuite[] memory wrappers = harness.declaredWrapperSuites(LibTestTokenRows.allRows());
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

    function testWrappersRefuseOtherWrapperBeacon(address wrong, uint256 usSeed, uint256 euSeed) external {
        vm.assume(wrong != LibProdTokenParams.wrapperBeacon());
        DeploySuite[] memory wrappers = harness.declaredWrapperSuites(oneRowPerRegion(usSeed, euSeed));
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            bindAddress(LibStoxConfig.WRAPPER_BEACON_NAME, wrong);
            for (uint256 j = 0; j < wrappers.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(WrapperBeaconMismatch.selector, wrong, LibProdTokenParams.wrapperBeacon())
                );
                harness.exposedPreDeployCheck(wrappers[j], networks[i]);
            }
        }
    }

    /// The wrapper beacon is the only binding a wrapper reads, so the token bindings stay unbound.
    function testWrappersAcceptPinnedWrapperBeacon() external {
        DeploySuite[] memory wrappers = harness.declaredWrapperSuites(LibTestTokenRows.allRows());
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindAddress(LibStoxConfig.WRAPPER_BEACON_NAME, LibProdTokenParams.wrapperBeacon());
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            for (uint256 j = 0; j < wrappers.length; j++) {
                harness.exposedPreDeployCheck(wrappers[j], networks[i]);
            }
        }
    }

    /// The token's address commits to the beacon name, not the implementation, so a pinned beacon serving any
    /// implementation but the current receipt vault, which carries the asset id hook, is refused.
    function testTokensRefuseVaultBeaconServingOtherImplementation(
        address implementation,
        uint256 usSeed,
        uint256 euSeed
    ) external {
        vm.assume(implementation != LibProdDeployCurrent.STOX_RECEIPT_VAULT);
        assumeNotPrecompile(implementation);
        assumeNotForgeAddress(implementation);
        vm.assume(implementation != LibProdTokenParams.vaultBeacon());
        vm.assume(implementation != address(harness));
        vm.assume(implementation.code.length == 0);
        placeVaultBeacon(implementation);
        DeploySuite[] memory tokens = harness.declaredTokenSuites(oneRowPerRegion(usSeed, euSeed));
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        BeaconImplementationMismatch.selector,
                        LibProdTokenParams.vaultBeacon(),
                        LibProdDeployCurrent.STOX_RECEIPT_VAULT,
                        implementation
                    )
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    /// A pinned vault beacon that is bound but has no code on the chain is refused with `VaultBeaconNotDeployed`.
    function testTokensRefuseABoundVaultBeaconWithNoCode() external {
        vm.etch(LibProdTokenParams.vaultBeacon(), "");
        DeploySuite[] memory tokens = harness.declaredTokenSuites(LibProdTokenConfig.testTokenConfigs());
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindPinned(networks[i].chainId);
            for (uint256 j = 0; j < tokens.length; j++) {
                vm.expectRevert(
                    abi.encodeWithSelector(VaultBeaconNotDeployed.selector, LibProdTokenParams.vaultBeacon())
                );
                harness.exposedPreDeployCheck(tokens[j], networks[i]);
            }
        }
    }

    /// A production row without an asset id has no token suite, so its key matches no token check: with nothing
    /// bound, the check passes instead of reverting on an unbound name.
    function testRowsWithoutAssetIdMatchNoTokenCheck() external view {
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 j = 0; j < production.length; j++) {
            if (bytes(production[j].assetId).length != 0) {
                continue;
            }
            DeploySuite memory suite;
            suite.suite = string.concat("stox-token-", vm.toLowercase(production[j].symbol));
            harness.exposedPreDeployCheck(suite, networks[0]);
        }
    }
}
