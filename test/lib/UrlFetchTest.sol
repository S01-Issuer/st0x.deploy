// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

abstract contract UrlFetchTest is Test {
    function fetch(string memory url) internal returns (string memory) {
        string[] memory command = new string[](7);
        command[0] = "curl";
        command[1] = "-sSfL";
        command[2] = "--retry";
        command[3] = "3";
        command[4] = "-A";
        command[5] = "st0x.deploy";
        command[6] = url;
        Vm.FfiResult memory result = vm.tryFfi(command);
        assertEq(result.exitCode, 0, string(result.stderr));
        return string(result.stdout);
    }
}
