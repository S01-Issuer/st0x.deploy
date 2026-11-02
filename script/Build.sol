// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildPointers} from "./BuildPointers.sol";
import {BuildPrivilegedAddresses} from "./BuildPrivilegedAddresses.sol";
import {BuildSubgraphNetworks} from "./BuildSubgraphNetworks.sol";
import {BuildIdealRoles} from "./BuildIdealRoles.sol";

/// @title Build
/// @notice The pre-build codegen script: pointers and deploy libs, then
/// `privileged-addresses.json`, `subgraph/networks.json` and `ideal-roles.json`.
contract Build is BuildPointers {
    function run() public override {
        super.run();
        new BuildPrivilegedAddresses().run();
        new BuildSubgraphNetworks().run();
        new BuildIdealRoles().run();
    }
}
