// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    CERTIFY,
    CONFISCATE_RECEIPT,
    CONFISCATE_SHARES,
    DEPOSIT,
    WITHDRAW
} from "rain-vats-0.2.4/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    CERTIFY_ADMIN,
    CONFISCATE_RECEIPT_ADMIN,
    CONFISCATE_SHARES_ADMIN,
    DEPOSIT_ADMIN,
    WITHDRAW_ADMIN
} from "rain-vats-0.2.4/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {UnnamedChain, UnnamedGrantee, UnnamedOwner, UnnamedRole} from "../../script/BuildPrivilegedAddresses.sol";
import {
    CANCEL_CORPORATE_ACTION_ADMIN,
    SCHEDULE_CORPORATE_ACTION_ADMIN
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {CANCEL_CORPORATE_ACTION, SCHEDULE_CORPORATE_ACTION} from "../../src/lib/LibCorporateAction.sol";
import {LibProdDeployV2BaseOverrides} from "../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {BuildPrivilegedAddressesHarness} from "./BuildPrivilegedAddressesHarness.sol";

struct Named {
    string name;
    address value;
}

contract BuildPrivilegedAddressesTest is Test {
    BuildPrivilegedAddressesHarness internal build = new BuildPrivilegedAddressesHarness();

    function testTopLevelFields() external view {
        string memory json = build.render();
        string[5] memory keys = ["version", "safePolicy", "authoriserImplementation", "beaconOwners", "chains"];
        assertEq(vm.parseJsonKeys(json, "$").length, keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            assertTrue(vm.keyExistsJson(json, string.concat(".", keys[i])), keys[i]);
        }
        assertEq(vm.parseJsonUint(json, ".version"), 1);
    }

    function testChainsAreTheDeploymentNetworksKeyedById() external view {
        string memory json = build.render();
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        uint256[5] memory ids = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        assertEq(networks.length, ids.length);
        assertEq(vm.parseJsonKeys(json, ".chains").length, ids.length);
        string[5] memory keys = ["network", "safe", "timelock", "authoriser", "authoriserGrants"];
        for (uint256 i = 0; i < ids.length; i++) {
            string memory at = chain(ids[i]);
            assertEq(vm.parseJsonKeys(json, at).length, keys.length);
            for (uint256 k = 0; k < keys.length; k++) {
                assertTrue(vm.keyExistsJson(json, string.concat(at, ".", keys[k])), keys[k]);
            }
            assertEq(vm.parseJsonString(json, string.concat(at, ".network")), networks[i]);
        }
    }

    function testSafePolicyIsThePinnedThresholdAndOwners() external view {
        string memory json = build.render();
        assertEq(vm.parseJsonKeys(json, ".safePolicy").length, 2);
        assertEq(vm.parseJsonUint(json, ".safePolicy.threshold"), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        address[] memory owners = LibSafeInvariants.expectedOwners();
        assertFalse(vm.keyExistsJson(json, index(".safePolicy.owners", owners.length)));
        for (uint256 i = 0; i < owners.length; i++) {
            assertPin(json, index(".safePolicy.owners", i), 0, owners[i]);
        }
    }

    function testAuthoriserImplementationIsWhatTheClonesDelegateTo() external view {
        string memory json = build.render();
        address impl = assertPin(
            json, ".authoriserImplementation", 0, LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
        );
        assertEq(
            keccak256(abi.encodePacked(hex"363d3d373d3d3d363d73", impl, hex"5af43d82803e903d91602b57fd5bf3")),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        );
    }

    function testBeaconOwnersCarryTheirConstantNames() external view {
        string memory json = build.render();
        assertEq(vm.parseJsonKeys(json, ".beaconOwners").length, 3);
        assertPin(json, ".beaconOwners.initial", 0, LibProdDeployV4.BEACON_INITIAL_OWNER);
        assertPin(json, ".beaconOwners.v2BaseReceipt", 0, LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER);
        assertPin(json, ".beaconOwners.v2BaseVault", 0, LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER);
    }

    function testChainPinsCarryTheirConstantNames() external view {
        string memory json = build.render();
        string[] memory keys = vm.parseJsonKeys(json, ".chains");
        for (uint256 c = 0; c < keys.length; c++) {
            uint256 id = vm.parseUint(keys[c]);
            string memory at = chain(id);
            assertPin(json, string.concat(at, ".safe"), id, LibSafeInvariants.safeForChainId(id));
            assertPin(json, string.concat(at, ".timelock"), id, LibTimelockInvariants.timelockForChainId(id));
            assertPin(json, string.concat(at, ".authoriser"), id, LibAuthoriserInvariants.authoriserForChainId(id));
        }
    }

    function testAuthoriserGrantsAreEachChainsMap() external view {
        string memory json = build.render();
        string[] memory keys = vm.parseJsonKeys(json, ".chains");
        for (uint256 c = 0; c < keys.length; c++) {
            uint256 id = vm.parseUint(keys[c]);
            string memory at = string.concat(chain(id), ".authoriserGrants");
            RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(
                LibSafeInvariants.safeForChainId(id), LibTimelockInvariants.timelockForChainId(id)
            );
            assertFalse(vm.keyExistsJson(json, index(at, grants.length)));
            for (uint256 j = 0; j < grants.length; j++) {
                string memory row = index(at, j);
                assertEq(vm.parseJsonKeys(json, row).length, 4);
                assertEq(vm.parseJsonBytes32(json, string.concat(row, ".role")), grants[j].role);
                assertEq(roleNamed(vm.parseJsonString(json, string.concat(row, ".roleName"))), grants[j].role);
                assertEq(vm.parseJsonAddress(json, string.concat(row, ".grantee")), grants[j].grantee);
                assertLowercase(vm.parseJsonString(json, string.concat(row, ".grantee")));
                assertEq(named(id, vm.parseJsonString(json, string.concat(row, ".granteeName"))), grants[j].grantee);
            }
        }
    }

    function testRunWritesTheRender() external {
        vm.removeFile("privileged-addresses.json");
        build.run();
        assertEq(vm.readFile("privileged-addresses.json"), build.render());
    }

    function testUnknownChainHasNoNetwork() external {
        vm.expectRevert(abi.encodeWithSelector(UnnamedChain.selector, uint256(10)));
        build.callNetwork(10);
    }

    function testUnknownChainHasNoSuffix() external {
        vm.expectRevert(abi.encodeWithSelector(UnnamedChain.selector, uint256(10)));
        build.callSuffix(10);
    }

    function testUnknownOwnerHasNoName() external {
        address owner = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        vm.expectRevert(abi.encodeWithSelector(UnnamedOwner.selector, owner));
        build.callOwnerName(owner);
    }

    function testUnknownRoleHasNoName() external {
        bytes32 role = keccak256("TRANSFER_SHARES");
        vm.expectRevert(abi.encodeWithSelector(UnnamedRole.selector, role));
        build.callRoleName(role);
    }

    function testUnknownGranteeHasNoName() external {
        address grantee = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        vm.expectRevert(abi.encodeWithSelector(UnnamedGrantee.selector, LibSafeInvariants.ETHEREUM_CHAIN_ID, grantee));
        build.callGranteeName(LibSafeInvariants.ETHEREUM_CHAIN_ID, grantee);
    }

    function assertPin(string memory json, string memory at, uint256 chainId, address expected)
        internal
        pure
        returns (address)
    {
        assertEq(vm.parseJsonKeys(json, at).length, 2);
        address value = vm.parseJsonAddress(json, string.concat(at, ".address"));
        assertEq(value, expected);
        assertLowercase(vm.parseJsonString(json, string.concat(at, ".address")));
        assertEq(named(chainId, vm.parseJsonString(json, string.concat(at, ".name"))), expected);
        return value;
    }

    function roleNamed(string memory name) internal pure returns (bytes32) {
        bytes32 key = keccak256(bytes(name));
        if (key == keccak256("DEPOSIT")) return DEPOSIT;
        if (key == keccak256("WITHDRAW")) return WITHDRAW;
        if (key == keccak256("CERTIFY")) return CERTIFY;
        if (key == keccak256("CONFISCATE_SHARES")) return CONFISCATE_SHARES;
        if (key == keccak256("CONFISCATE_RECEIPT")) return CONFISCATE_RECEIPT;
        if (key == keccak256("SCHEDULE_CORPORATE_ACTION")) return SCHEDULE_CORPORATE_ACTION;
        if (key == keccak256("CANCEL_CORPORATE_ACTION")) return CANCEL_CORPORATE_ACTION;
        if (key == keccak256("DEPOSIT_ADMIN")) return DEPOSIT_ADMIN;
        if (key == keccak256("WITHDRAW_ADMIN")) return WITHDRAW_ADMIN;
        if (key == keccak256("CERTIFY_ADMIN")) return CERTIFY_ADMIN;
        if (key == keccak256("CONFISCATE_SHARES_ADMIN")) return CONFISCATE_SHARES_ADMIN;
        if (key == keccak256("CONFISCATE_RECEIPT_ADMIN")) return CONFISCATE_RECEIPT_ADMIN;
        if (key == keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN")) return SCHEDULE_CORPORATE_ACTION_ADMIN;
        if (key == keccak256("CANCEL_CORPORATE_ACTION_ADMIN")) return CANCEL_CORPORATE_ACTION_ADMIN;
        revert(string.concat("no role constant named ", name));
    }

    function named(uint256 chainId, string memory name) internal pure returns (address) {
        Named[] memory table = new Named[](15);
        table[0] = Named("STOX_TOKEN_OWNER_SAFE_OWNER_1", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_1);
        table[1] = Named("STOX_TOKEN_OWNER_SAFE_OWNER_2", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_2);
        table[2] = Named("STOX_TOKEN_OWNER_SAFE_OWNER_3", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_3);
        table[3] = Named("STOX_TOKEN_OWNER_SAFE_OWNER_4", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_4);
        table[4] = Named("STOX_TOKEN_OWNER_SAFE_OWNER_5", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_5);
        table[5] = Named("STOX_TOKEN_OWNER_SAFE_OWNER_TDM", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_OWNER_TDM);
        table[6] = Named(
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1",
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
        );
        table[7] = Named("BEACON_INITIAL_OWNER", LibProdDeployV4.BEACON_INITIAL_OWNER);
        table[8] = Named("RECEIPT_BEACON_OWNER", LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER);
        table[9] = Named("VAULT_BEACON_OWNER", LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER);
        if (chainId != 0) {
            table[10] = Named("GRANTEE_SERVICE_3D0C", LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
            table[11] = Named("GRANTEE_ORCHESTRATOR", LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        }
        if (chainId == 8453) {
            table[12] = Named("STOX_TOKEN_OWNER_SAFE", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
            table[13] = Named("STOX_GOVERNANCE_TIMELOCK", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
            table[14] = Named("STOX_PROD_AUTHORISER_V4_CLONE", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE);
        } else if (chainId == 1) {
            table[12] = Named("STOX_TOKEN_OWNER_SAFE_ETHEREUM", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM);
            table[13] =
                Named("STOX_GOVERNANCE_TIMELOCK_ETHEREUM", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM);
            table[14] =
                Named("STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM);
        } else if (chainId == 999) {
            table[12] = Named("STOX_TOKEN_OWNER_SAFE_HYPEREVM", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM);
            table[13] =
                Named("STOX_GOVERNANCE_TIMELOCK_HYPEREVM", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM);
            table[14] =
                Named("STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM);
        } else if (chainId == 4663) {
            table[12] = Named("STOX_TOKEN_OWNER_SAFE_ROBINHOOD", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD);
            table[13] =
                Named("STOX_GOVERNANCE_TIMELOCK_ROBINHOOD", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD);
            table[14] = Named(
                "STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD
            );
        } else if (chainId == 56) {
            table[12] = Named("STOX_TOKEN_OWNER_SAFE_BSC", LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC);
            table[13] = Named("STOX_GOVERNANCE_TIMELOCK_BSC", LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC);
            table[14] = Named("STOX_PROD_AUTHORISER_V4_CLONE_BSC", LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC);
        }
        for (uint256 i = 0; i < table.length; i++) {
            if (bytes(table[i].name).length > 0 && keccak256(bytes(table[i].name)) == keccak256(bytes(name))) {
                return table[i].value;
            }
        }
        revert(string.concat("no constant named ", name, " on chain ", vm.toString(chainId)));
    }

    function chain(uint256 chainId) internal pure returns (string memory) {
        return string.concat(".chains.", vm.toString(chainId));
    }

    function index(string memory at, uint256 i) internal pure returns (string memory) {
        return string.concat(at, "[", vm.toString(i), "]");
    }

    function assertLowercase(string memory value) internal pure {
        assertEq(value, vm.toLowercase(value));
    }
}
