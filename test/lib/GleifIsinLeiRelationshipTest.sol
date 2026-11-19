// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

abstract contract GleifIsinLeiRelationshipTest is Test {
    string internal constant GLEIF_ISIN_LEI = "https://mapping.gleif.org/api/v2/isin-lei/latest/download";

    /// Every `stride`th ISIN of GLEIF's latest ISIN-to-LEI relationship file, from the first, one per line.
    function gleifIsins(uint256 stride) internal returns (bytes memory) {
        string[] memory command = new string[](5);
        command[0] = "bash";
        command[1] = "-c";
        // `gzip` inflates the zip's single deflated member.
        command[2] = "set -euo pipefail; curl -sSfL --retry 3 -A st0x.deploy \"$0\" | gzip -dc | awk -F, -v stride=\"$1\""
            " 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == \"ISIN\") c = i; if (!c) exit 1; next }"
            " (NR - 2) % stride == 0 { print $c }'";
        command[3] = GLEIF_ISIN_LEI;
        command[4] = vm.toString(stride);
        Vm.FfiResult memory result = vm.tryFfi(command);
        assertEq(result.exitCode, 0, string(result.stderr));
        return result.stdout;
    }
}
