// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {RetireDirectSignerRoles} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";

contract RetireDirectSignerRolesHarness is RetireDirectSignerRoles {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20260831-retire-direct-signer-roles-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callAssertOrchestratorPathEnabled(IAccessControl acl, address orchestrator) external view {
        assertOrchestratorPathEnabled(acl, orchestrator);
    }

    function callOperation(address authoriser, address controller)
        external
        view
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        return operation(authoriser, controller);
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view {
        assertPostState();
    }

    function callAssertPostRetireState(IAccessControl acl, address orchestrator, address safeAddr) external view {
        assertPostRetireState(acl, orchestrator, safeAddr);
    }
}
