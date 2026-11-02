// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.29/src/lib/LibConfigRegistry.sol";
import {
    LibOffchainAssetReceiptVaultRbac,
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
} from "rain-vats-0.2.16/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {LibStoxConfig} from "./LibStoxConfig.sol";
import {LibAuthoriserInvariants} from "./LibAuthoriserInvariants.sol";

/// @param network The network the binding was resolved on.
/// @param name The binding.
/// @param field The decoded field that differs.
/// @param expected The declared value.
/// @param actual The resolved value.
error TokenBindingMismatch(string network, bytes32 name, string field, address expected, address actual);

/// @title LibStoxTokenBindings
/// @notice Confirms the bindings production tokens initialize from resolve,
/// typed, to what the declaration expects on each network.
library LibStoxTokenBindings {
    bytes32 internal constant ADDRESS_VALUE_TYPE_HASH = keccak256("address");

    function checkOnNetworks(Vm vm, string[] memory networks, address beacon) internal {
        uint256[] memory forkIds = LibRainDeploy.createForks(vm, networks);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            check(networks[i], beacon);
        }
    }

    function check(string memory network, address beacon) internal view {
        compare(
            network, LibStoxConfig.VAULT_BEACON_NAME, "beacon", beacon, resolveAddress(LibStoxConfig.VAULT_BEACON_NAME)
        );
        address timelock = resolveAddress(LibStoxConfig.GOVERNANCE_TIMELOCK_NAME);
        checkRbac(
            network, LibStoxConfig.RBAC_US_NAME, timelock, LibAuthoriserInvariants.authoriserForChainId(block.chainid)
        );
        checkRbac(
            network, LibStoxConfig.RBAC_EU_NAME, timelock, LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
        );
    }

    function checkRbac(string memory network, bytes32 name, address owner, address authorizer) internal view {
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(
            LibStoxConfig.ROOT_AUTHORITY, name, OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
        );
        OffchainAssetReceiptVaultRbacV1 memory rbac =
            LibOffchainAssetReceiptVaultRbac.decodeCanonical(LibStoxConfig.ROOT_AUTHORITY, name, value);
        compare(network, name, "owner", owner, rbac.owner);
        compare(network, name, "authorizer", authorizer, address(rbac.authorizer));
    }

    function resolveAddress(bytes32 name) internal view returns (address) {
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(LibStoxConfig.ROOT_AUTHORITY, name, ADDRESS_VALUE_TYPE_HASH);
        return abi.decode(value, (address));
    }

    function compare(string memory network, bytes32 name, string memory field, address expected, address actual)
        internal
        pure
    {
        if (actual != expected) {
            revert TokenBindingMismatch(network, name, field, expected, actual);
        }
    }
}
