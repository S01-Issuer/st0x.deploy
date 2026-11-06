// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "rain-deploy-0.1.30/src/lib/LibRainDeployDeclaration.sol";
import {ZOLTU_MECHANISM_ID} from "rain-deploy-0.1.30/src/lib/LibRainDeployZoltuMechanism.sol";
import {LibReleasedSuites} from "../src/lib/LibReleasedSuites.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibEuAuthoriserClone} from "../src/lib/LibEuAuthoriserClone.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibTokenMetadata} from "../src/lib/LibTokenMetadata.sol";
import {LibUnderlyingNamingRollout} from "../src/lib/LibUnderlyingNamingRollout.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibProdDeployV2} from "../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV2BaseOverrides} from "../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";

/// @title BuildExpectedState
/// @notice Writes `expected-state.json`, the live state the dashboard checks. Under `chains`, per deployment network:
/// `network`, `beaconSetDeployer`, `beacons` (beacon, codehash, implementation, renamedImplementation once
/// `renameMigration` is recorded, owner), the token-owner `safe`
/// lock-down, the `timelock`, the `orchestrator`, the V4
/// `authoriser` and `euAuthoriser` clones (address, codehash), every released Zoltu suite declared on that network
/// under `zoltu` (key, address, codehash), `renameMigration` (the migration whose record on the chain selects each
/// token's renamed metadata), and per production token under `tokens`: `underlying`, `name`, `renamedName`, `symbol`,
/// `decimals`, `wrappedTokenVaultName`, `wrappedTokenVaultRenamedName`, `wrappedTokenVaultSymbol`,
/// `wrappedTokenVaultRenamedSymbol`, `wrappedTokenVaultDecimals`, `receiptVault`, `receipt`, `wrappedTokenVault`,
/// `receiptVaultReceipt` (`receiptVault.receipt()`), `receiptManager` (`receipt.manager()`), `wrappedTokenVaultAsset`
/// (`wrappedTokenVault.asset()`), the
/// per-leg beacons `receiptVaultBeacon`, `receiptBeacon`, `wrappedTokenVaultBeacon`, the per-leg proxy codehashes
/// `receiptVaultCodehash`, `receiptCodehash`,
/// `wrappedTokenVaultCodehash`, `owner` and `authoriser`. Under `v2`, per network V2 was checked on: `network`,
/// `deployments` (each `LibProdDeployV2` key, address, codehash), `beaconSetDeployer`, and `receiptBeacon`,
/// `receiptVaultBeacon`, `wrappedTokenVaultBeacon` (beacon, implementation, owner).
contract BuildExpectedState is Script {
    string internal constant PATH = "expected-state.json";

    /// The implementations `renameMigration`'s beacon batch moves the beacons to.
    function renamedImplementations(uint256 chainId) internal pure returns (address[4] memory) {
        address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(chainId);
        impls[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX] = LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION;
        impls[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX] =
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION;
        return impls;
    }

    function beaconsJson(uint256 chainId, string memory key) internal returns (string[] memory) {
        address[4] memory derived = LibBeaconInvariants.prodDerivedBeaconsForChainId(chainId);
        address[4] memory implementations = LibBeaconInvariants.prodExpectedImplementationsForChainId(chainId);
        bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(chainId);
        address[4] memory renamed = renamedImplementations(chainId);
        address owner = LibTimelockInvariants.timelockForChainId(chainId);
        string[] memory rows = new string[](derived.length);
        for (uint256 i = 0; i < derived.length; i++) {
            string memory row = string.concat(key, ".beacon.", vm.toString(i));
            vm.serializeAddress(row, "beacon", derived[i]);
            vm.serializeBytes32(row, "codehash", codehashes[i]);
            vm.serializeAddress(row, "implementation", implementations[i]);
            vm.serializeAddress(row, "renamedImplementation", renamed[i]);
            rows[i] = vm.serializeAddress(row, "owner", owner);
        }
        return rows;
    }

    function safeProxyCodehashes() internal pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = LibSafe.SAFE_V1_4_1_PROXY_CODEHASH;
        hashes[1] = LibSafe.SAFE_V1_3_0_PROXY_CODEHASH;
        return hashes;
    }

    function safeSingletons() internal pure returns (address[] memory) {
        address[] memory singletons = new address[](2);
        singletons[0] = LibSafe.SAFE_V1_4_1_L1_SINGLETON;
        singletons[1] = LibSafe.SAFE_V1_4_1_L2_SINGLETON;
        return singletons;
    }

    function safeSingletonCodehashes() internal pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = LibSafe.SAFE_V1_4_1_L1_SINGLETON_CODEHASH;
        hashes[1] = LibSafe.SAFE_V1_4_1_L2_SINGLETON_CODEHASH;
        return hashes;
    }

    function safeJson(uint256 chainId, string memory key) internal returns (string memory) {
        string memory at = string.concat(key, ".safe");
        vm.serializeAddress(at, "address", LibSafeInvariants.safeForChainId(chainId));
        vm.serializeAddress(at, "owners", LibSafeInvariants.expectedOwners());
        vm.serializeBytes32(at, "proxyCodehashes", safeProxyCodehashes());
        vm.serializeAddress(at, "singletons", safeSingletons());
        vm.serializeBytes32(at, "singletonCodehashes", safeSingletonCodehashes());
        vm.serializeString(at, "version", LibSafe.SAFE_V1_4_1_VERSION);
        vm.serializeAddress(at, "modules", new address[](0));
        vm.serializeAddress(at, "guard", address(0));
        vm.serializeAddress(at, "fallbackHandler", LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER);
        vm.serializeBytes32(at, "fallbackHandlerCodehash", LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_CODEHASH);
        return vm.serializeUint(at, "threshold", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
    }

    /// Grants are not emitted: ideal-roles.json carries them keyed by clone address.
    function authoriserJson(string memory at, address clone, bytes32 codehash) internal returns (string memory) {
        vm.serializeAddress(at, "address", clone);
        return vm.serializeBytes32(at, "codehash", codehash);
    }

    /// Roles are not emitted: ideal-roles.json carries them keyed by timelock address.
    function timelockJson(uint256 chainId, string memory key) internal returns (string memory) {
        string memory at = string.concat(key, ".timelock");
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        vm.serializeAddress(at, "address", timelock);
        vm.serializeBytes32(at, "codehash", LibTimelockInvariants.timelockCodehash(timelock));
        return vm.serializeUint(at, "minDelay", LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    function orchestratorJson(uint256 chainId, string memory key) internal returns (string memory) {
        string memory at = string.concat(key, ".orchestrator");
        vm.serializeAddress(at, "setDeployer", LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30);
        vm.serializeAddress(at, "beacon", LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON);
        vm.serializeBytes32(at, "beaconCodehash", LibBeaconInvariants.UPGRADEABLE_BEACON_CODEHASH_0_1_30);
        vm.serializeAddress(at, "implementation", LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30);
        vm.serializeAddress(at, "owner", LibTimelockInvariants.timelockForChainId(chainId));
        return vm.serializeAddress(at, "instance", LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
    }

    function tokenMetadataJson(string memory row, uint256 i, string memory underlying) internal {
        TokenConfig memory config = LibProdTokenConfig.configOf(underlying);
        vm.serializeString(row, "underlying", underlying);
        bool renames = LibUnderlyingNamingRollout.renamesRow(i);
        vm.serializeString(row, "name", LibTokenMetadata.vaultName(config, false));
        vm.serializeString(row, "renamedName", LibTokenMetadata.vaultName(config, renames));
        vm.serializeString(row, "symbol", config.symbol);
        vm.serializeUint(row, "decimals", LibTokenMetadata.RECEIPT_VAULT_DECIMALS);
        vm.serializeString(row, "wrappedTokenVaultName", LibTokenMetadata.wrappedName(config, false));
        vm.serializeString(row, "wrappedTokenVaultRenamedName", LibTokenMetadata.wrappedName(config, renames));
        vm.serializeString(row, "wrappedTokenVaultSymbol", LibTokenMetadata.wrappedSymbol(config, false));
        vm.serializeString(row, "wrappedTokenVaultRenamedSymbol", LibTokenMetadata.wrappedSymbol(config, renames));
        vm.serializeUint(row, "wrappedTokenVaultDecimals", LibTokenMetadata.WRAPPED_TOKEN_VAULT_DECIMALS);
    }

    function tokenLegsJson(
        string memory row,
        TokenInstance memory token,
        address[4] memory beacons,
        bytes32[4] memory proxyCodehashes
    ) internal {
        vm.serializeAddress(row, "receiptVault", token.receiptVault);
        vm.serializeAddress(row, "receipt", token.receipt);
        vm.serializeAddress(row, "wrappedTokenVault", token.wrappedTokenVault);
        vm.serializeAddress(row, "receiptVaultReceipt", token.receipt);
        vm.serializeAddress(row, "receiptManager", token.receiptVault);
        vm.serializeAddress(row, "wrappedTokenVaultAsset", token.receiptVault);
        vm.serializeAddress(row, "receiptVaultBeacon", beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
        vm.serializeAddress(row, "receiptBeacon", beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
        vm.serializeAddress(
            row, "wrappedTokenVaultBeacon", beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
        vm.serializeBytes32(
            row, "receiptVaultCodehash", proxyCodehashes[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]
        );
        vm.serializeBytes32(row, "receiptCodehash", proxyCodehashes[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
        vm.serializeBytes32(
            row, "wrappedTokenVaultCodehash", proxyCodehashes[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
    }

    function tokensJson(uint256 chainId, string memory key) internal returns (string[] memory) {
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(chainId);
        address usAuthoriser = LibAuthoriserInvariants.authoriserForChainId(chainId);
        address[4] memory beacons = LibBeaconInvariants.prodDerivedBeaconsForChainId(chainId);
        bytes32[4] memory proxyCodehashes = LibBeaconInvariants.prodTokenProxyCodehashesForChainId(chainId);
        string[] memory rows = new string[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            string memory row = string.concat(key, ".token.", vm.toString(i));
            tokenMetadataJson(row, i, tokens[i].underlying);
            tokenLegsJson(row, tokens[i], beacons, proxyCodehashes);
            vm.serializeAddress(row, "owner", LibTimelockInvariants.timelockForChainId(chainId));
            rows[i] = vm.serializeAddress(
                row, "authoriser", LibTokenInvariants.expectedAuthoriser(tokens[i].underlying, usAuthoriser, chainId)
            );
        }
        return rows;
    }

    function releasedSuites() internal pure returns (DeploySuite[] memory) {
        DeployDeclaration memory declared;
        LibRainDeployDeclaration.setNetworks(declared, LibStoxDeployNetworks.deploymentNetworks());
        LibRainDeployDeclaration.addReleased(declared, LibReleasedSuites.releasedSuites());
        return declared.released;
    }

    function zoltuOn(DeploySuite memory suite, uint256 chainId) internal pure returns (bool) {
        return LibRainDeployDeclaration.mechanismIdOf(suite) == ZOLTU_MECHANISM_ID
            && LibRainDeploy.hasChainId(LibRainDeploy.declaredNetworkConfigs(suite.networks), chainId);
    }

    function zoltuJson(uint256 chainId, string memory key) internal returns (string[] memory) {
        DeploySuite[] memory suites = releasedSuites();
        uint256 count = 0;
        for (uint256 i = 0; i < suites.length; i++) {
            if (zoltuOn(suites[i], chainId)) {
                count++;
            }
        }
        string[] memory rows = new string[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < suites.length; i++) {
            if (!zoltuOn(suites[i], chainId)) {
                continue;
            }
            string memory row = string.concat(key, ".zoltu.", vm.toString(j));
            vm.serializeString(row, "key", suites[i].suite);
            vm.serializeAddress(row, "address", suites[i].storedDeployedAddress);
            rows[j] = vm.serializeBytes32(row, "codehash", suites[i].storedBytecodeHash);
            j++;
        }
        return rows;
    }

    /// Base's beacons are the V1 set deployer's; elsewhere the 0.1.1 set deployer's.
    function beaconSetDeployer(uint256 chainId) internal pure returns (address) {
        return LibBeaconInvariants.runsBaseBeaconSet(chainId)
            ? LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
            : LibBeaconInvariants.prodBeaconSetDeployerForChainId(chainId);
    }

    function chainJson(SupportedNetwork memory network) internal returns (string memory) {
        uint256 chainId = network.chainId;
        string memory key = vm.toString(chainId);
        vm.serializeString(key, "network", network.name);
        vm.serializeAddress(key, "beaconSetDeployer", beaconSetDeployer(chainId));
        vm.serializeString(key, "beacons", beaconsJson(chainId, key));
        vm.serializeString(key, "safe", safeJson(chainId, key));
        vm.serializeString(key, "timelock", timelockJson(chainId, key));
        vm.serializeString(key, "orchestrator", orchestratorJson(chainId, key));
        vm.serializeString(
            key,
            "authoriser",
            authoriserJson(
                string.concat(key, ".authoriser"),
                LibAuthoriserInvariants.authoriserForChainId(chainId),
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
            )
        );
        vm.serializeString(
            key,
            "euAuthoriser",
            authoriserJson(
                string.concat(key, ".euAuthoriser"),
                LibAuthoriserInvariants.euAuthoriserForChainId(chainId),
                LibEuAuthoriserClone.cloneDeployedCodehash()
            )
        );
        vm.serializeString(key, "zoltu", zoltuJson(chainId, key));
        vm.serializeBytes32(key, "renameMigration", LibStoxMigrations.EXECUTE_UNDERLYING_NAMING);
        return vm.serializeString(key, "tokens", tokensJson(chainId, key));
    }

    function v2Networks() internal pure returns (string[] memory) {
        string[] memory names = new string[](5);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        names[1] = LibRainDeploy.BASE;
        names[2] = LibRainDeploy.BASE_SEPOLIA;
        names[3] = LibRainDeploy.FLARE;
        names[4] = LibRainDeploy.POLYGON;
        return names;
    }

    function v2DeploymentJson(string memory key, uint256 i, string memory name, address deployed, bytes32 codehash)
        internal
        returns (string memory)
    {
        string memory row = string.concat(key, ".deployment.", vm.toString(i));
        vm.serializeString(row, "key", name);
        vm.serializeAddress(row, "address", deployed);
        return vm.serializeBytes32(row, "codehash", codehash);
    }

    function v2DeploymentsJson(string memory key) internal returns (string[] memory) {
        string[] memory rows = new string[](9);
        rows[0] = v2DeploymentJson(
            key, 0, "StoxReceipt", LibProdDeployV2.STOX_RECEIPT, LibProdDeployV2.STOX_RECEIPT_CODEHASH
        );
        rows[1] = v2DeploymentJson(
            key, 1, "StoxReceiptVault", LibProdDeployV2.STOX_RECEIPT_VAULT, LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH
        );
        rows[2] = v2DeploymentJson(
            key,
            2,
            "StoxWrappedTokenVault",
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH
        );
        rows[3] = v2DeploymentJson(
            key,
            3,
            "StoxUnifiedDeployer",
            LibProdDeployV2.STOX_UNIFIED_DEPLOYER,
            LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH
        );
        rows[4] = v2DeploymentJson(
            key,
            4,
            "StoxWrappedTokenVaultBeacon",
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH
        );
        rows[5] = v2DeploymentJson(
            key,
            5,
            "StoxOffchainAssetReceiptVaultBeaconSetDeployer",
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );
        rows[6] = v2DeploymentJson(
            key,
            6,
            "StoxWrappedTokenVaultBeaconSetDeployer",
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );
        rows[7] = v2DeploymentJson(
            key,
            7,
            "StoxOffchainAssetReceiptVaultAuthorizerV1",
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH
        );
        rows[8] = v2DeploymentJson(
            key,
            8,
            "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
        );
        return rows;
    }

    function v2BeaconJson(string memory at, address beacon, address implementation, address owner)
        internal
        returns (string memory)
    {
        vm.serializeAddress(at, "beacon", beacon);
        vm.serializeAddress(at, "implementation", implementation);
        return vm.serializeAddress(at, "owner", owner);
    }

    /// Receipt and receipt-vault beacons are the set deployer's constructor CREATEs at nonce 1 and 2.
    function v2Json(SupportedNetwork memory network) internal returns (string memory) {
        string memory key = string.concat("v2.", vm.toString(network.chainId));
        bool isBase = network.chainId == LibSafeInvariants.BASE_CHAIN_ID;
        address setDeployer = LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER;
        vm.serializeString(key, "network", network.name);
        vm.serializeString(key, "deployments", v2DeploymentsJson(key));
        vm.serializeAddress(key, "beaconSetDeployer", setDeployer);
        vm.serializeString(
            key,
            "receiptBeacon",
            v2BeaconJson(
                string.concat(key, ".receiptBeacon"),
                LibBeaconInvariants.createAddress(setDeployer, 1),
                isBase ? LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION : LibProdDeployV2.STOX_RECEIPT,
                isBase ? LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER : LibProdDeployV2.BEACON_INITIAL_OWNER
            )
        );
        vm.serializeString(
            key,
            "receiptVaultBeacon",
            v2BeaconJson(
                string.concat(key, ".receiptVaultBeacon"),
                LibBeaconInvariants.createAddress(setDeployer, 2),
                isBase ? LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION : LibProdDeployV2.STOX_RECEIPT_VAULT,
                isBase ? LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER : LibProdDeployV2.BEACON_INITIAL_OWNER
            )
        );
        return vm.serializeString(
            key,
            "wrappedTokenVaultBeacon",
            v2BeaconJson(
                string.concat(key, ".wrappedTokenVaultBeacon"),
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
                LibProdDeployV2.BEACON_INITIAL_OWNER
            )
        );
    }

    function render() public returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory chains;
        for (uint256 i = 0; i < networks.length; i++) {
            chains = vm.serializeString("chains", vm.toString(networks[i].chainId), chainJson(networks[i]));
        }
        SupportedNetwork[] memory v2 = LibRainDeploy.declaredNetworkConfigs(v2Networks());
        string memory v2Chains;
        for (uint256 i = 0; i < v2.length; i++) {
            v2Chains = vm.serializeString("v2", vm.toString(v2[i].chainId), v2Json(v2[i]));
        }
        vm.serializeUint("root", "version", 1);
        vm.serializeString("root", "v2", v2Chains);
        return vm.serializeString("root", "chains", chains);
    }

    function run() external {
        vm.writeJson(render(), PATH);
    }
}
