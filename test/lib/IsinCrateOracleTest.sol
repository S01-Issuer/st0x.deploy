// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

/// Differential oracle over the Rust `isin` crate 0.1.19, run from the flake's
/// `isin-oracle` over `vm.ffi`.
abstract contract IsinCrateOracleTest is Test {
    string internal sOracle;

    function setUp() public virtual {
        string[] memory command = new string[](5);
        command[0] = "nix";
        command[1] = "build";
        command[2] = "--no-link";
        command[3] = "--print-out-paths";
        command[4] = ".#isin-oracle";
        sOracle = string.concat(string(ffiOk(command)), "/bin/isin-oracle");
    }

    function ffiOk(string[] memory command) internal returns (bytes memory) {
        Vm.FfiResult memory result = vm.tryFfi(command);
        assertEq(result.exitCode, 0, string(result.stderr));
        return result.stdout;
    }

    function oracle(string memory op, bytes memory value) internal returns (bytes memory) {
        string[] memory command = new string[](3);
        command[0] = sOracle;
        command[1] = op;
        command[2] = vm.toString(value);
        return ffiOk(command);
    }

    /// Whether `isin::parse` accepts `value`.
    function crateValid(bytes memory value) internal returns (bool) {
        return abi.decode(oracle("valid", value), (bool));
    }

    /// The check digit `isin::checksum::checksum_table` computes for
    /// `payload`, which must be `A-Z` and `0-9` only.
    function crateCheckDigit(bytes memory payload) internal returns (bytes1) {
        return bytes1(abi.decode(oracle("check-digit", payload), (uint8)));
    }
}
