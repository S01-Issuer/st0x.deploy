// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";

import {GrantEuAuthoriserRoles} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";

contract GrantEuAuthoriserRolesHarness is GrantEuAuthoriserRoles {
    string internal sArtifactTag;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261006-grant-eu-authoriser-roles-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
    }

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view {
        assertPostState();
    }
}
