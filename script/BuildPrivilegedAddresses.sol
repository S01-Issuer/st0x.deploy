// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
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

    function hex20(address a) internal pure returns (string memory) {
        return vm.toLowercase(vm.toString(a));
    }

    function addressList(address[] memory list, string memory pad) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < list.length; i++) {
            json = string.concat(json, i == 0 ? "\n" : ",\n", pad, "  \"", hex20(list[i]), "\"");
        }
        return string.concat(json, list.length == 0 ? "]" : string.concat("\n", pad, "]"));
    }

    function beaconsJson(uint256 chainId) internal pure returns (string memory) {
        address[4] memory pinned = LibBeaconInvariants.prodPinnedBeaconsForChainId(chainId);
        address[4] memory implementations = LibBeaconInvariants.prodImplementationsForChainId(chainId);
        address[4] memory v1 = LibBeaconInvariants.prodV1ImplementationsForChainId(chainId);
        string memory json = "[";
        for (uint256 i = 0; i < pinned.length; i++) {
            json = string.concat(
                json,
                i == 0 ? "\n" : ",\n",
                "        {\n          \"beacon\": \"",
                hex20(pinned[i]),
                "\",\n          \"implementation\": \"",
                hex20(implementations[i]),
                "\",\n          \"v1Implementation\": \"",
                hex20(v1[i]),
                "\"\n        }"
            );
        }
        return string.concat(json, "\n      ]");
    }

    function chainJson(SupportedNetwork memory network) internal pure returns (string memory) {
        uint256 chainId = network.chainId;
        string memory json = string.concat(
            "    \"",
            vm.toString(chainId),
            "\": {\n      \"network\": \"",
            network.name,
            "\",\n      \"safe\": \"",
            hex20(LibSafeInvariants.safeForChainId(chainId)),
            "\",\n      \"timelock\": \"",
            hex20(LibTimelockInvariants.timelockForChainId(chainId)),
            "\",\n      \"authoriser\": \"",
            hex20(LibAuthoriserInvariants.authoriserForChainId(chainId))
        );
        return string.concat(
            json,
            "\",\n      \"beaconSetDeployer\": \"",
            hex20(LibBeaconInvariants.prodBeaconSetDeployerForChainId(chainId)),
            "\",\n      \"beacons\": ",
            beaconsJson(chainId),
            ",\n      \"receiptVaults\": ",
            addressList(LibTokenInvariants.productionReceiptVaultsForChainId(chainId), "      "),
            "\n    }"
        );
    }

    function render() public pure returns (string memory) {
        string memory out = string.concat(
            "{\n  \"version\": 1,\n  \"safePolicy\": {\n    \"threshold\": ",
            vm.toString(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD),
            ",\n    \"owners\": ",
            addressList(LibSafeInvariants.expectedOwners(), "    "),
            "\n  },\n  \"authoriserImplementation\": \"",
            hex20(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1),
            "\",\n  \"beaconOwners\": {\n    \"initial\": \"",
            hex20(LibProdDeployV1.BEACON_INITIAL_OWNER),
            "\",\n    \"v2BaseReceipt\": \"",
            hex20(LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER),
            "\",\n    \"v2BaseVault\": \"",
            hex20(LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER),
            "\"\n  },\n  \"chains\": {"
        );
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            out = string.concat(out, i == 0 ? "\n" : ",\n", chainJson(networks[i]));
        }
        return string.concat(out, "\n  }\n}\n");
    }

    function run() external {
        vm.writeFile(PATH, render());
    }
}
