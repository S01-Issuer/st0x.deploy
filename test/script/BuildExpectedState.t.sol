// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {BuildExpectedState} from "../../script/BuildExpectedState.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

contract BuildExpectedStateTest is Test {
    BuildExpectedState internal build = new BuildExpectedState();

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function testVersionIsOne() external {
        assertEq(vm.parseJsonUint(build.render(), ".version"), 1);
    }

    function testChainsAreTheDeploymentNetworksKeyedByChainId() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        assertEq(vm.parseJsonKeys(json, ".chains").length, nets.length);
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(vm.parseJsonString(json, string.concat(chain(nets[i]), ".network")), nets[i].name);
        }
    }

    function testBeaconsAreTheInUseSetAtTheirExpectedImplementationsOwnedByTheTimelock() external {
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
            address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(id);
            string memory list = string.concat(at, ".beacons");
            assertFalse(vm.keyExistsJson(json, index(list, pinned.length)));
            for (uint256 i = 0; i < pinned.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".beacon")), pinned[i]);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".implementation")), impls[i]);
                assertEq(
                    vm.parseJsonAddress(json, string.concat(row, ".owner")), LibTimelockInvariants.timelockForChainId(id)
                );
            }
        }
    }

    /// Fixed example from the Ethereum leg: the receipt beacon is read from the beacon set deployer, so its slot is
    /// empty, and it must serve the 0.1.30 receipt.
    function testEthereumReceiptBeaconIsDeployerResolvedAt0_1_30() external {
        string memory json = build.render();
        string memory row = ".chains.1.beacons[0]";
        assertEq(vm.parseJsonAddress(json, string.concat(row, ".beacon")), address(0));
        assertEq(vm.parseJsonAddress(json, string.concat(row, ".implementation")), LibProdDeployV4.STOX_RECEIPT_0_1_30);
        assertEq(
            vm.parseJsonAddress(json, ".chains.1.beaconSetDeployer"),
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );
    }

    function testSafeIsTheChainsSafeWithThePinnedPolicy() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            string memory at = string.concat(chain(nets[i]), ".safe");
            assertEq(
                vm.parseJsonAddress(json, string.concat(at, ".address")),
                LibSafeInvariants.safeForChainId(nets[i].chainId)
            );
            assertEq(
                vm.parseJsonUint(json, string.concat(at, ".threshold")), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
            address[] memory owners = LibSafeInvariants.expectedOwners();
            string memory list = string.concat(at, ".owners");
            assertFalse(vm.keyExistsJson(json, index(list, owners.length)));
            for (uint256 j = 0; j < owners.length; j++) {
                assertEq(vm.parseJsonAddress(json, index(list, j)), owners[j]);
            }
        }
    }

    function testTokensAreTheChainsTableWithRegionRoutedAuthorisers() external {
        string memory json = build.render();
        SupportedNetwork[] memory nets = networks();
        for (uint256 c = 0; c < nets.length; c++) {
            uint256 id = nets[c].chainId;
            TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(id);
            string memory list = string.concat(chain(nets[c]), ".tokens");
            assertFalse(vm.keyExistsJson(json, index(list, tokens.length)));
            for (uint256 i = 0; i < tokens.length; i++) {
                string memory row = index(list, i);
                assertEq(vm.parseJsonString(json, string.concat(row, ".underlying")), tokens[i].underlying);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".receiptVault")), tokens[i].receiptVault);
                address expected = isEu(tokens[i].underlying)
                    ? LibAuthoriserInvariants.euAuthoriserForChainId(id)
                    : LibAuthoriserInvariants.authoriserForChainId(id);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".authoriser")), expected);
            }
        }
    }

    /// Fixed examples on Base: tMC is the EU token, on the EU clone; tMSTR is US, on the V4 clone.
    function testBaseMcIsOnTheEuCloneAndMstrOnTheV4Clone() external {
        string memory json = build.render();
        string memory list = ".chains.8453.tokens";
        uint256 n = LibTokenInvariants.productionTokensBase().length;
        bool sawMc;
        bool sawMstr;
        for (uint256 i = 0; i < n; i++) {
            string memory row = index(list, i);
            bytes32 underlying = keccak256(bytes(vm.parseJsonString(json, string.concat(row, ".underlying"))));
            address authoriser = vm.parseJsonAddress(json, string.concat(row, ".authoriser"));
            if (underlying == keccak256("MC")) {
                assertEq(authoriser, 0xDB9152e46c1D140DB6a6f814461f21c571F3275e);
                sawMc = true;
            } else if (underlying == keccak256("MSTR")) {
                assertEq(authoriser, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE);
                sawMstr = true;
            }
        }
        assertTrue(sawMc && sawMstr);
    }

    function testRunWritesTheRender() external {
        vm.removeFile("expected-state.json");
        build.run();
        assertEq(
            keccak256(vm.parseJson(vm.readFile("expected-state.json"))), keccak256(vm.parseJson(build.render()))
        );
    }

    function isEu(string memory underlying) internal pure returns (bool) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            if (keccak256(bytes(configs[i].underlying)) == keccak256(bytes(underlying))) {
                return configs[i].region == Region.EU;
            }
        }
        revert("no config");
    }

    function chain(SupportedNetwork memory network) internal pure returns (string memory) {
        return string.concat(".chains.", vm.toString(network.chainId));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }
}
