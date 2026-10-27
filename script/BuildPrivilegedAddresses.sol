// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.26/src/lib/LibRainDeploy.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2BaseOverrides} from "../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../src/lib/LibTokenInvariants.sol";

/// @title BuildPrivilegedAddresses
/// @notice Writes `privileged-addresses.json`: the Safe policy, the authoriser implementation, the beacon owners, and
/// per deployment network the Safe, timelock, authoriser, production beacons and receipt vaults. `address(0)` is none.
contract BuildPrivilegedAddresses is Script {
    string internal constant PATH = "privileged-addresses.json";

    function beaconsJson(uint256 chainId, string memory key) internal returns (string[] memory) {
        address[4] memory pinned = LibBeaconInvariants.prodPinnedBeaconsForChainId(chainId);
        address[4] memory implementations = LibBeaconInvariants.prodImplementationsForChainId(chainId);
        address[4] memory v1 = LibBeaconInvariants.prodV1ImplementationsForChainId(chainId);
        string[] memory rows = new string[](pinned.length);
        for (uint256 i = 0; i < pinned.length; i++) {
            string memory row = string.concat(key, ".beacon.", vm.toString(i));
            vm.serializeAddress(row, "beacon", pinned[i]);
            vm.serializeAddress(row, "implementation", implementations[i]);
            rows[i] = vm.serializeAddress(row, "v1Implementation", v1[i]);
        }
        return rows;
    }

    function chainJson(SupportedNetwork memory network) internal returns (string memory) {
        uint256 chainId = network.chainId;
        string memory key = vm.toString(chainId);
        vm.serializeString(key, "network", network.name);
        vm.serializeAddress(key, "safe", LibSafeInvariants.safeForChainId(chainId));
        vm.serializeAddress(key, "timelock", LibTimelockInvariants.timelockForChainId(chainId));
        vm.serializeAddress(key, "authoriser", LibAuthoriserInvariants.authoriserForChainId(chainId));
        vm.serializeAddress(key, "beaconSetDeployer", LibBeaconInvariants.prodBeaconSetDeployerForChainId(chainId));
        vm.serializeString(key, "beacons", beaconsJson(chainId, key));
        return vm.serializeAddress(key, "receiptVaults", LibTokenInvariants.productionReceiptVaultsForChainId(chainId));
    }

    function render() public returns (string memory) {
        vm.serializeUint("safePolicy", "threshold", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        string memory safePolicy = vm.serializeAddress("safePolicy", "owners", LibSafeInvariants.expectedOwners());
        vm.serializeAddress("beaconOwners", "initial", LibProdDeployV1.BEACON_INITIAL_OWNER);
        vm.serializeAddress("beaconOwners", "v2BaseReceipt", LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER);
        string memory beaconOwners =
            vm.serializeAddress("beaconOwners", "v2BaseVault", LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER);
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        string memory chains;
        for (uint256 i = 0; i < networks.length; i++) {
            chains = vm.serializeString("chains", vm.toString(networks[i].chainId), chainJson(networks[i]));
        }
        vm.serializeUint("root", "version", 1);
        vm.serializeString("root", "safePolicy", safePolicy);
        vm.serializeAddress(
            "root", "authoriserImplementation", LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
        );
        vm.serializeString("root", "beaconOwners", beaconOwners);
        return vm.serializeString("root", "chains", chains);
    }

    function run() external {
        vm.writeJson(render(), PATH);
    }
}
