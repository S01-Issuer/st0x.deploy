// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibConfigRegistryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {IAuthorizeV1} from "rain-vats-0.2.9/src/interface/IAuthorizeV1.sol";
import {IAuthorizableV1} from "rain-vats-0.2.9/src/interface/IAuthorizableV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.9/src/interface/IReceiptVaultV3.sol";
import {OffchainAssetReceiptVaultRbacV1} from "rain-vats-0.2.9/src/lib/LibOffchainAssetReceiptVaultRbac.sol";

import {DeployTestTokens} from "../../script/20261026-deploy-test-tokens.s.sol";
import {StoxCorporateActionsFacet} from "../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceipt} from "../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {Region} from "../../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxTestTokens, TestTokenAddresses} from "../../src/lib/LibStoxTestTokens.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title DeployTestTokensProdTest
/// @notice The script against each production chain's live state, after the
/// steps it waits on are simulated: the token beacon upgrade, and the root
/// authority binding the chain's beacons and each region's RBAC. Every chain
/// lands the same token, receipt and wrapper addresses, on its own beacons,
/// timelock and authorisers.
contract DeployTestTokensProdTest is Test {
    function deployIfAbsent(bytes memory creationCode, address expected) internal {
        if (expected.code.length == 0) {
            address deployed = LibRainDeploy.deployZoltu(creationCode);
            assertEq(deployed, expected, "candidate address");
        }
    }

    function bind(bytes32 name, bytes memory value) internal {
        vm.warp(block.timestamp + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV3(LibStoxConfig.ROOT_AUTHORITY, name, value);
    }

    function upgrade(address beacon, address implementation) internal {
        vm.prank(Ownable(beacon).owner());
        UpgradeableBeacon(beacon).upgradeTo(implementation);
    }

    function checkChain(string memory network) internal {
        vm.createSelectFork(network);
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);

        deployIfAbsent(type(StoxReceipt).creationCode, LibProdDeployCurrent.STOX_RECEIPT);
        deployIfAbsent(type(StoxReceiptVault).creationCode, LibProdDeployCurrent.STOX_RECEIPT_VAULT);
        deployIfAbsent(
            type(StoxCorporateActionsFacet).creationCode, LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(chainId);
        upgrade(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], LibProdDeployCurrent.STOX_RECEIPT);
        upgrade(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], LibProdDeployCurrent.STOX_RECEIPT_VAULT);

        bind(LibStoxConfig.RECEIPT_BEACON_NAME, abi.encode(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]));
        bind(LibStoxConfig.VAULT_BEACON_NAME, abi.encode(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]));
        bind(
            LibStoxConfig.WRAPPER_BEACON_NAME, abi.encode(beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX])
        );
        address usAuthoriser = LibAuthoriserInvariants.authoriserForChainId(chainId);
        address euAuthoriser = LibAuthoriserInvariants.euAuthoriserForChainId(chainId);
        bind(
            LibStoxConfig.US_RBAC_NAME,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: timelock, authorizer: IAuthorizeV1(usAuthoriser)}))
        );
        bind(
            LibStoxConfig.EU_RBAC_NAME,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: timelock, authorizer: IAuthorizeV1(euAuthoriser)}))
        );

        new DeployTestTokens().run();

        checkRegion(Region.US, timelock, usAuthoriser);
        checkRegion(Region.EU, timelock, euAuthoriser);
    }

    function checkRegion(Region region, address timelock, address authoriser) internal view {
        TestTokenAddresses memory pinned = LibStoxTestTokens.addresses(region);
        assertEq(address(IReceiptVaultV3(payable(pinned.token)).receipt()), pinned.receipt, "receipt");
        assertEq(IERC4626(pinned.wrapper).asset(), pinned.token, "wrapper asset");
        assertEq(Ownable(pinned.token).owner(), timelock, "owner");
        assertEq(address(IAuthorizableV1(pinned.token).authorizer()), authoriser, "authoriser");
    }

    function testDeployTestTokensBase() external {
        checkChain(LibRainDeploy.BASE);
    }

    function testDeployTestTokensEthereum() external {
        checkChain(LibStoxDeployNetworks.ETHEREUM);
    }

    function testDeployTestTokensHyperEvm() external {
        checkChain(LibStoxDeployNetworks.HYPEREVM);
    }

    function testDeployTestTokensRobinhood() external {
        checkChain(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testDeployTestTokensBsc() external {
        checkChain(LibStoxDeployNetworks.BSC);
    }
}
