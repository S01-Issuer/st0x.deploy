// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    LibRainDeployRegistryBeaconProxy,
    RegistryBeaconProxyTarget
} from "rain-factory-0.2.7/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {LibStoxTokenProxy} from "../generated/LibStoxTokenProxy.sol";

error TokenProxyForeignCode(string network, uint256 row, address proxy);

error TokenProxyMissing(string network, uint256 row, address proxy);

error TokenPinMismatch(string network, address account);

library LibStoxTokenGaps {
    function checkPin(string memory network, address account, bytes memory runtimeCode) internal view {
        if (keccak256(account.code) != keccak256(runtimeCode)) {
            revert TokenPinMismatch(network, account);
        }
    }

    function fill(Vm vm, string memory network, address deployer, RegistryBeaconProxyTarget[] memory targets)
        internal
    {
        bytes32 expected = keccak256(LibStoxTokenProxy.RUNTIME_CODE);
        for (uint256 i = 0; i < targets.length; i++) {
            address proxy = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]);
            if (proxy.code.length == 0) {
                LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployStep(
                    vm, network, deployer, abi.encode(targets[i])
                );
                if (keccak256(proxy.code) != expected) {
                    revert TokenProxyForeignCode(network, i, proxy);
                }
            } else if (keccak256(proxy.code) != expected) {
                revert TokenProxyForeignCode(network, i, proxy);
            }
        }
    }

    function check(string memory network, RegistryBeaconProxyTarget[] memory targets) internal view {
        bytes32 expected = keccak256(LibStoxTokenProxy.RUNTIME_CODE);
        for (uint256 i = 0; i < targets.length; i++) {
            address proxy = LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(targets[i]);
            if (proxy.code.length == 0) {
                revert TokenProxyMissing(network, i, proxy);
            }
            if (keccak256(proxy.code) != expected) {
                revert TokenProxyForeignCode(network, i, proxy);
            }
        }
    }
}
