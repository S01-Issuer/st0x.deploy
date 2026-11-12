// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {QsepSetFleetAuthoriser} from "../../script/20261111-qsep-set-fleet-authoriser.s.sol";

/// @title QsepSetFleetAuthoriserHarness
/// @notice The script, writing its artifact under a per-test stem so parallel
/// tests never read each other's file.
contract QsepSetFleetAuthoriserHarness is QsepSetFleetAuthoriser {
    string internal sStem;

    constructor(string memory stem) {
        sStem = stem;
    }

    function artifactPath() internal view override returns (string memory) {
        return string.concat("out/20261111-qsep-set-fleet-authoriser-", sStem, "-", vm.toString(block.chainid), ".json");
    }

    function path() external view returns (string memory) {
        return artifactPath();
    }
}
