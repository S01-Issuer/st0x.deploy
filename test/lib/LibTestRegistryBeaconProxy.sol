// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    REGISTRY_BEACON_PROXY_PREFIX,
    REGISTRY_BEACON_PROXY_SUFFIX
} from "rain-extrospection-0.1.16/src/lib/LibExtrospectRegistryBeaconProxy.sol";

library LibTestRegistryBeaconProxy {
    /// Places `RegistryBeaconProxy` runtime bytecode over `beacon` at `at`.
    function etch(Vm vm, address at, address beacon) internal {
        vm.etch(
            at,
            abi.encodePacked(
                REGISTRY_BEACON_PROXY_PREFIX, bytes32(uint256(uint160(beacon))), REGISTRY_BEACON_PROXY_SUFFIX
            )
        );
    }
}
