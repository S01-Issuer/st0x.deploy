// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.29/src/lib/LibSafe.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {
    BYTECODE_HASH as TIMELOCK_BYTECODE_HASH
} from "rain-deploy-0.1.29/src/generated/0_1_18/TimelockController.sol";

/// @title BuildExpectedState
/// @notice Writes `expected-state.json`: per deployment network, the state CI asserts live. Each in-use beacon in
/// `LibBeaconInvariants` index order with its expected implementation and owner (`beacon` is `address(0)` where
/// `beaconSetDeployer` resolves it), the token-owner Safe with its owner set and threshold, and each production
/// token's receipt vault with its region-routed authoriser.
contract BuildExpectedState is Script {
    string internal constant PATH = "expected-state.json";

    function beaconsJson(uint256 chainId, string memory key) internal returns (string[] memory) {
        address[4] memory pinned = LibBeaconInvariants.prodPinnedBeaconsForChainId(chainId);
        address[4] memory implementations = LibBeaconInvariants.prodExpectedImplementationsForChainId(chainId);
        bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(chainId);
        address owner = LibTimelockInvariants.timelockForChainId(chainId);
        string[] memory rows = new string[](pinned.length);
        for (uint256 i = 0; i < pinned.length; i++) {
            string memory row = string.concat(key, ".beacon.", vm.toString(i));
            vm.serializeAddress(row, "beacon", pinned[i]);
            vm.serializeBytes32(row, "codehash", codehashes[i]);
            vm.serializeAddress(row, "implementation", implementations[i]);
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
    function authoriserJson(string memory at, address clone) internal returns (string memory) {
        vm.serializeAddress(at, "address", clone);
        return vm.serializeBytes32(at, "codehash", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH);
    }

    /// Roles are not emitted: ideal-roles.json carries them keyed by timelock address.
    function timelockJson(uint256 chainId, string memory key) internal returns (string memory) {
        string memory at = string.concat(key, ".timelock");
        vm.serializeAddress(at, "address", LibTimelockInvariants.timelockForChainId(chainId));
        vm.serializeBytes32(at, "codehash", TIMELOCK_BYTECODE_HASH);
        return vm.serializeUint(at, "minDelay", LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    function tokensJson(uint256 chainId, string memory key) internal returns (string[] memory) {
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(chainId);
        address usAuthoriser = LibAuthoriserInvariants.authoriserForChainId(chainId);
        string[] memory rows = new string[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            string memory row = string.concat(key, ".token.", vm.toString(i));
            vm.serializeString(row, "underlying", tokens[i].underlying);
            vm.serializeAddress(row, "receiptVault", tokens[i].receiptVault);
            rows[i] = vm.serializeAddress(
                row, "authoriser", LibTokenInvariants.expectedAuthoriser(tokens[i].underlying, usAuthoriser, chainId)
            );
        }
        return rows;
    }

    function chainJson(SupportedNetwork memory network) internal returns (string memory) {
        uint256 chainId = network.chainId;
        string memory key = vm.toString(chainId);
        vm.serializeString(key, "network", network.name);
        vm.serializeAddress(key, "beaconSetDeployer", LibBeaconInvariants.prodBeaconSetDeployerForChainId(chainId));
        vm.serializeString(key, "beacons", beaconsJson(chainId, key));
        vm.serializeString(key, "safe", safeJson(chainId, key));
        vm.serializeString(key, "timelock", timelockJson(chainId, key));
        vm.serializeString(
            key,
            "authoriser",
            authoriserJson(string.concat(key, ".authoriser"), LibAuthoriserInvariants.authoriserForChainId(chainId))
        );
        vm.serializeString(
            key,
            "euAuthoriser",
            authoriserJson(string.concat(key, ".euAuthoriser"), LibAuthoriserInvariants.euAuthoriserForChainId(chainId))
        );
        return vm.serializeString(key, "tokens", tokensJson(chainId, key));
    }

    function render() public returns (string memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory chains;
        for (uint256 i = 0; i < networks.length; i++) {
            chains = vm.serializeString("chains", vm.toString(networks[i].chainId), chainJson(networks[i]));
        }
        vm.serializeUint("root", "version", 1);
        return vm.serializeString("root", "chains", chains);
    }

    function run() external {
        vm.writeJson(render(), PATH);
    }
}
