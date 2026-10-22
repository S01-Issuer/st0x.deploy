// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    DeployAuthoriserClone,
    boundCloneStep,
    boundZoltuDeployStep
} from "../../script/20261022-deploy-authoriser-clone.s.sol";

/// @dev Exposes the script's internals.
contract DeployAuthoriserCloneHarness is DeployAuthoriserClone {
    function callAssertCloneState(address clone) external view {
        assertCloneState(clone);
    }

    function callBoundZoltuDeployStep(string memory network, address deployer, bytes memory creationCode)
        external
        returns (address)
    {
        return boundZoltuDeployStep(vm, network, deployer, creationCode);
    }

    function callBoundCloneStep(string memory network, address deployer, bytes memory data) external returns (address) {
        return boundCloneStep(vm, network, deployer, data);
    }
}
