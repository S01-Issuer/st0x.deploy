// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibConfigRegistryRegister} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryRegister.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.18/src/interface/ICloneableFactoryV7.sol";
import {RegistryBeaconProxyParams} from "rain-factory-0.2.18/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.25/src/lib/LibOffchainAssetReceiptVaultRbac.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {
    IStoxTokenConfigV1,
    StoxTokenConfigV1,
    STOX_TOKEN_CONFIG_V1_TAG
} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTokenMetadata, TokenMetadataState} from "../../../src/lib/LibTokenMetadata.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestTokenRows} from "../../lib/LibTestTokenRows.sol";
import {DeployPreDeployCheckHarness} from "../../script/DeployPreDeployCheckHarness.sol";

/// @title StoxDeploySuitesTokenRowsBaseForkTest
/// @notice On a Base fork pinned before the release, with the release up, every token row, production and test, deploys
/// its token suite from a keyless address through the real `Deploy` pre-flight, initialized from its listing at deploy
/// and named from its snapshot row if it is a production row, else from its listing; a front-run deploy by someone else
/// is the same token at the same address.
/// @dev Each suite runs the broadcaster's address, chain id and dependency checks and `preDeployCheck`, not its seat
/// checks.
contract StoxDeploySuitesTokenRowsBaseForkTest is Test, StoxDeploySuites {
    /// No release name is bound and no release suite is deployed at this block.
    uint256 internal constant BASE_BLOCK = 57530000;

    address internal constant DEPLOYER =
        address(uint160(uint256(keccak256("st0x.test.token-rows-base-fork.deployer"))));
    address internal constant FRONT_RUNNER =
        address(uint160(uint256(keccak256("st0x.test.token-rows-base-fork.front-runner"))));

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
        LibTestDeploy.bind(vm, LibRegistryAuthority.ROOT_AUTHORITY, name, valueType, value);
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

    /// Suite `name` through the broadcaster's per-network steps: its derived address checked against its recorded one,
    /// its fork checks, the real pre-flight, then its deploy step as `deployer` unless code is already at its recorded
    /// address, with the stored code hash checked either way.
    function broadcast(DeployDeclaration memory declared, string memory name, address deployer)
        internal
        returns (address)
    {
        DeploySuite memory suite = suiteByName(declared, name);
        address recorded = recordedAddress(declared, suite, base.chainId);
        assertEq(deployedAddress(declared, suite, base.chainId), recorded, name);
        LibRainDeploy.selectCheckedFork(vm, base, vm.activeFork(), suite.dependencies);
        harness.exposedPreDeployCheck(suite, base);
        LibRainDeploy.deployStepToSelectedFork(
            vm,
            base.name,
            deployer,
            deployStep(declared, suite),
            deployStepData(declared, suite, base.chainId),
            recorded,
            suite.storedBytecodeHash
        );
        return recorded;
    }

    /// Suite `name`, which has no code at the pinned block, deployed by `DEPLOYER`.
    function dispatch(DeployDeclaration memory declared, string memory name) internal returns (address) {
        assertEq(recordedAddress(declared, suiteByName(declared, name), base.chainId).code.length, 0, name);
        return broadcast(declared, name, DEPLOYER);
    }

    /// The release a token deploy needs: the timelock, the underlying snapshot, the implementations and the beacons,
    /// with the root authority's bindings. In its own call frame, because the declaration is large and memory is only
    /// freed when a frame returns.
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
        dispatch(declared, UNDERLYING_SNAPSHOT_ROOT);
        uint256 shardCount = underlyingSnapshotShardSuites().length;
        for (uint256 i = 0; i < shardCount; i++) {
            dispatch(declared, underlyingSnapshotShardSuite(i));
        }
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

    /// Suite `name`, broadcast by `deployer`, in its own call frame.
    function broadcastSuite(string memory name, address deployer) external returns (address) {
        return broadcast(declaration(), name, deployer);
    }

    /// A production row reads its snapshot row; a test row has none and reads its listing.
    function readState(uint256 row) internal pure returns (TokenMetadataState) {
        return row < LibProdTokenConfig.productionTokenConfigs().length
            ? TokenMetadataState.Renamed
            : TokenMetadataState.Listed;
    }

    /// `token` reads `config` in `state`, and `logs` hold exactly one `StoxTokenInitialized` from its listing, of
    /// `data`.
    function assertInitialized(
        TokenConfig memory config,
        TokenMetadataState state,
        bytes memory data,
        address token,
        Vm.Log[] memory logs
    ) internal view {
        StoxReceiptVault vault = StoxReceiptVault(payable(token));
        bool renamed = state == TokenMetadataState.Renamed;
        assertEq(vault.name(), LibTokenMetadata.vaultName(config, state), config.underlying);
        assertEq(vault.symbol(), LibTokenMetadata.vaultSymbol(config, state), config.underlying);
        assertEq(
            IStoxUnderlyingV2(token).underlyingSymbol(),
            renamed ? config.ticker : config.listingTicker,
            config.underlying
        );
        assertEq(
            IStoxUnderlyingV2(token).underlyingName(),
            renamed ? config.underlyingName : config.listingName,
            config.underlying
        );
        assertEq(vault.owner(), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, config.underlying);
        assertEq(
            address(vault.authorizer()),
            config.region == Region.US
                ? LibAuthoriserInvariants.authoriserForChainId(base.chainId)
                : LibAuthoriserInvariants.euAuthoriserForChainId(base.chainId),
            config.underlying
        );
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == token && logs[i].topics[0] == IStoxTokenConfigV1.StoxTokenInitialized.selector) {
                StoxTokenConfigV1 memory emitted = abi.decode(logs[i].data, (StoxTokenConfigV1));
                assertEq(abi.encode(STOX_TOKEN_CONFIG_V1_TAG, emitted), data, config.underlying);
                assertEq(abi.encode(emitted.assetId), abi.encode(config.assetId), config.underlying);
                count++;
            }
        }
        assertEq(count, 1, config.underlying);
    }

    function testEveryTokenRowDeploysKeylessAndReadsItsSnapshotRowElseItsListing() external {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        DeploySuite[] memory suites = harness.declaredTokenSuites(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            address token = ICloneableFactoryV7(params[i].factory)
                .predictRegistryBeaconProxyAddress(
                    params[i].registry, params[i].authority, params[i].beaconName, params[i].data, params[i].salt
                );
            assertEq(token.code.length, 0, configs[i].underlying);
            vm.recordLogs();
            assertEq(this.broadcastSuite(suites[i].suite, DEPLOYER), token, configs[i].underlying);
            assertInitialized(configs[i], readState(i), params[i].data, token, vm.getRecordedLogs());
        }
    }

    /// The broadcaster run after the front-run finds the token already there and deploys nothing.
    function testAFrontRunDeployIsTheSameTokenAtTheSameAddress() external {
        TokenConfig[] memory configs = LibTestTokenRows.allRows();
        RegistryBeaconProxyParams[] memory params = LibProdTokenParams.tokenParams(configs);
        DeploySuite[] memory suites = harness.declaredTokenSuites(configs);
        for (uint256 i = 0; i < configs.length; i++) {
            vm.recordLogs();
            vm.prank(FRONT_RUNNER);
            address frontRun = ICloneableFactoryV7(params[i].factory)
                .registryBeaconProxy(
                    params[i].registry, params[i].authority, params[i].beaconName, params[i].data, params[i].salt
                );
            assertEq(this.broadcastSuite(suites[i].suite, DEPLOYER), frontRun, configs[i].underlying);
            assertInitialized(configs[i], readState(i), params[i].data, frontRun, vm.getRecordedLogs());
        }
    }
}
