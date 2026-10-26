// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {BuildPrivilegedAddresses} from "../../script/BuildPrivilegedAddresses.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IST0xVaultBeaconSet} from "../../src/interface/IST0xVaultBeaconSet.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2BaseOverrides} from "../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

contract BuildPrivilegedAddressesTest is Test {
    BuildPrivilegedAddresses internal build = new BuildPrivilegedAddresses();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testSafePolicyIsThePinnedThresholdAndOwners() external {
        string memory json = build.render();
        assertEq(vm.parseJsonUint(json, ".safePolicy.threshold"), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        assertAddresses(json, ".safePolicy.owners", LibSafeInvariants.expectedOwners());
    }

    function testAuthoriserImplementationIsTheV4Pin() external {
        assertEq(
            vm.parseJsonAddress(build.render(), ".authoriserImplementation"),
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
        );
    }

    function testBeaconOwnersAreTheV1AndV2Pins() external {
        string memory json = build.render();
        assertEq(vm.parseJsonAddress(json, ".beaconOwners.initial"), LibProdDeployV1.BEACON_INITIAL_OWNER);
        assertEq(
            vm.parseJsonAddress(json, ".beaconOwners.v2BaseReceipt"), LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER
        );
        assertEq(
            vm.parseJsonAddress(json, ".beaconOwners.v2BaseVault"), LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER
        );
    }

    function testChainsAreTheDeploymentNetworksKeyedByChainId() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".chains").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(vm.parseJsonString(json, string.concat(chain(nets[i]), ".network")), nets[i].name);
        }
    }

    function testChainPrincipalsAreTheChainsPins() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 id = nets[i].chainId;
            string memory at = chain(nets[i]);
            assertEq(vm.parseJsonAddress(json, string.concat(at, ".safe")), LibSafeInvariants.safeForChainId(id));
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".timelock")), LibTimelockInvariants.timelockForChainId(id)
            );
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".authoriser")),
                LibAuthoriserInvariants.authoriserForChainId(id)
            );
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".euAuthoriser")),
                LibAuthoriserInvariants.euAuthoriserForChainId(id)
            );
        }
    }

    function testBeaconsAreTheChainsProductionSet() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            string memory at = chain(nets[c]);
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".beaconSetDeployer")),
                LibBeaconInvariants.prodBeaconSetDeployerForChainId(id)
            );
            address[4] memory pinned = LibBeaconInvariants.prodPinnedBeaconsForChainId(id);
            address[4] memory implementations = LibBeaconInvariants.prodImplementationsForChainId(id);
            address[4] memory v1 = LibBeaconInvariants.prodV1ImplementationsForChainId(id);
            string memory list = string.concat(at, ".beacons");
            assertFalse(vm.keyExistsJson(json, index(list, pinned.length)));
            for (uint256 i = 0; i < pinned.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".beacon")), pinned[i]);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".implementation")), implementations[i]);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".v1Implementation")), v1[i]);
            }
        }
    }

    function testUnpinnedBeaconsAreTheDeployersReceiptAndReceiptVaultBeacons() external {
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            address deployer = LibBeaconInvariants.prodBeaconSetDeployerForChainId(id);
            address[4] memory live = LibBeaconInvariants.prodPinnedBeaconsForChainId(id);
            if (deployer != address(0)) {
                vm.etch(deployer, hex"00");
                vm.mockCall(
                    deployer, abi.encodeCall(IST0xVaultBeaconSet.iReceiptBeacon, ()), abi.encode(address(0x1111))
                );
                vm.mockCall(
                    deployer,
                    abi.encodeCall(IST0xVaultBeaconSet.iOffchainAssetReceiptVaultBeacon, ()),
                    abi.encode(address(0x2222))
                );
                live[LibBeaconInvariants.RECEIPT_BEACON_INDEX] = address(0x1111);
                live[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX] = address(0x2222);
            }
            address[4] memory resolved = LibBeaconInvariants.prodBeaconsForChainId(id);
            for (uint256 i = 0; i < resolved.length; i++) {
                assertEq(resolved[i], live[i]);
                assertTrue(live[i] != address(0));
            }
            vm.clearMockedCalls();
        }
    }

    function testReceiptVaultsAreEachChainsTokenTable() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            assertAddresses(
                json,
                string.concat(chain(nets[i]), ".receiptVaults"),
                LibTokenInvariants.productionReceiptVaultsForChainId(nets[i].chainId)
            );
        }
    }

    function testRunWritesTheRender() external {
        vm.removeFile("privileged-addresses.json");
        build.run();
        assertEq(
            keccak256(vm.parseJson(vm.readFile("privileged-addresses.json"))), keccak256(vm.parseJson(build.render()))
        );
    }

    function chain(SupportedNetwork memory network) internal pure returns (string memory) {
        return string.concat(".chains.", vm.toString(network.chainId));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function assertAddresses(string memory json, string memory at, address[] memory expected) internal view {
        assertFalse(vm.keyExistsJson(json, index(at, expected.length)));
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(vm.parseJsonAddress(json, index(at, i)), expected[i]);
        }
    }
}
