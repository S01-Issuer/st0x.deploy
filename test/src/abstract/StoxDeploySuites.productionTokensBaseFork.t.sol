// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryRegister} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryRegister.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {RegistryBeaconProxyParams} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.20/src/lib/LibOffchainAssetReceiptVaultRbac.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {DeployPreDeployCheckHarness} from "../../script/DeployPreDeployCheckHarness.sol";

/// @title StoxDeploySuitesProductionTokensBaseForkTest
/// @notice On a Base fork pinned before the release, with the release up, every production row's token suite deploys
/// from a keyless address through the real `Deploy` pre-flight and is named from its listing at deploy; a front-run
/// deploy by someone else is the same token at the same address.
/// @dev Each suite runs the broadcaster's chain id and dependency checks and `preDeployCheck`, not its seat checks.
contract StoxDeploySuitesProductionTokensBaseForkTest is Test, StoxDeploySuites {
    /// No release name is bound and no release suite is deployed at this block.
    uint256 internal constant BASE_BLOCK = 57530000;

    address internal constant DEPLOYER =
        address(uint160(uint256(keccak256("st0x.test.production-tokens-base-fork.deployer"))));
    address internal constant FRONT_RUNNER =
        address(uint160(uint256(keccak256("st0x.test.production-tokens-base-fork.front-runner"))));

    DeployPreDeployCheckHarness internal harness;
    SupportedNetwork internal base;

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE, BASE_BLOCK);
        harness = new DeployPreDeployCheckHarness();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == block.chainid) {
                base = networks[i];
            }
        }
        assertEq(base.chainId, LibSafeInvariants.BASE_CHAIN_ID, "base network");
        this.deployRelease();
    }

    function isBound(bytes32 name) internal view returns (bool) {
        (, uint256 registeredAt,) = LibConfigRegistryRegister.currentBinding(LibRegistryAuthority.ROOT_AUTHORITY, name);
        return registeredAt != 0;
    }

    function bind(bytes32 name, string memory valueType, bytes memory value) internal {
        assertFalse(isBound(name), "bound at the pinned block");
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
            .registerV5(LibRegistryAuthority.ROOT_AUTHORITY, name, valueType, value, "");
    }

    function bindRbac(bytes32 name, address authorizer) internal {
        bind(
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(
                OffchainAssetReceiptVaultRbacV1({
                    owner: LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, authorizer: IAuthorizeV1(authorizer)
                })
            )
        );
    }

    /// Suite `name` through the broadcaster's per-network steps: its fork checks, the real pre-flight, then its deploy
    /// step as `deployer` unless code is already at its stored address, with the stored code hash checked either way.
    function broadcast(DeployDeclaration memory declared, string memory name, address deployer)
        internal
        returns (address)
    {
        DeploySuite memory suite = suiteByName(declared, name);
        LibRainDeploy.selectCheckedFork(vm, base, vm.activeFork(), suite.dependencies);
        harness.exposedPreDeployCheck(suite, base);
        LibRainDeploy.deployStepToSelectedFork(
            vm,
            base.name,
            deployer,
            deployStep(declared, suite),
            deployStepData(declared, suite, base.chainId),
            suite.storedDeployedAddress,
            suite.storedBytecodeHash
        );
        return suite.storedDeployedAddress;
    }

    /// Suite `name`, which has no code at the pinned block, deployed by `DEPLOYER`.
    function dispatch(DeployDeclaration memory declared, string memory name) internal returns (address) {
        assertEq(suiteByName(declared, name).storedDeployedAddress.code.length, 0, name);
        return broadcast(declared, name, DEPLOYER);
    }

    /// The release a token deploy needs: the timelock, the implementations and the beacons, with the root authority's
    /// bindings. In its own call frame, because the declaration is large and memory is only freed when a frame returns.
    function deployRelease() external {
        DeployDeclaration memory declared = declaration();
        bind(
            LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME,
            "address",
            abi.encode(LibSafeInvariants.safeForChainId(base.chainId))
        );
        assertEq(dispatch(declared, GOVERNANCE_TIMELOCK), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, "timelock");
        bind(
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        dispatch(declared, FACET);
        dispatch(declared, RECEIPT);
        dispatch(declared, RECEIPT_VAULT);
        address receiptBeacon = dispatch(declared, RECEIPT_BEACON);
        address vaultBeacon = dispatch(declared, RECEIPT_VAULT_BEACON);
        bind(LibStoxConfig.VAULT_BEACON_NAME, "address", abi.encode(vaultBeacon));
        bind(LibStoxConfig.RECEIPT_BEACON_NAME, "address", abi.encode(receiptBeacon));
        bindRbac(LibStoxConfig.RBAC_US_NAME, LibAuthoriserInvariants.authoriserForChainId(base.chainId));
        bindRbac(LibStoxConfig.RBAC_EU_NAME, LibAuthoriserInvariants.euAuthoriserForChainId(base.chainId));
    }

    /// Production row `index`'s token suite, broadcast by `deployer`, in its own call frame.
    function broadcastRow(uint256 index, address deployer) external returns (address) {
        TokenConfig memory config = LibProdTokenConfig.productionTokenConfigs()[index];
        return broadcast(declaration(), string.concat(TOKEN_PREFIX, lowercase(config.symbol)), deployer);
    }

    function assertNamedFromListing(TokenConfig memory config, address token) internal view {
        StoxReceiptVault vault = StoxReceiptVault(payable(token));
        assertEq(vault.name(), string.concat(config.listingName, ST0X_NAME_SUFFIX), config.underlying);
        assertEq(vault.symbol(), string.concat("t", config.listingTicker), config.underlying);
        assertEq(vault.owner(), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, config.underlying);
        assertEq(
            address(vault.authorizer()),
            config.region == Region.US
                ? LibAuthoriserInvariants.authoriserForChainId(base.chainId)
                : LibAuthoriserInvariants.euAuthoriserForChainId(base.chainId),
            config.underlying
        );
    }

    function testEveryProductionRowDeploysKeylessAndIsNamedFromItsListing() external {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            address token = ICloneableFactoryV7(params[i].factory)
                .predictRegistryBeaconProxyAddress(
                    params[i].registry, params[i].authority, params[i].beaconName, params[i].data, params[i].salt
                );
            assertEq(token.code.length, 0, configs[i].underlying);
            assertEq(this.broadcastRow(i, DEPLOYER), token, configs[i].underlying);
            assertNamedFromListing(configs[i], token);
        }
    }

    /// The broadcaster run after the front-run finds the token already there and deploys nothing.
    function testAFrontRunDeployIsTheSameTokenAtTheSameAddress() external {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            vm.prank(FRONT_RUNNER);
            address frontRun = ICloneableFactoryV7(params[i].factory)
                .registryBeaconProxy(
                    params[i].registry, params[i].authority, params[i].beaconName, params[i].data, params[i].salt
                );
            assertEq(this.broadcastRow(i, DEPLOYER), frontRun, configs[i].underlying);
            assertNamedFromListing(configs[i], frontRun);
        }
    }
}
