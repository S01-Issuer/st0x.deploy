// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {GenerateMetadata} from "../script/GenerateMetadata.s.sol";

contract GenerateMetadataFfiTest is Test {
    string constant OUTPUT = "launch/metadata/rai3577ffitest.json";

    function testGenerateMetadataThroughFfi() external {
        vm.setEnv(
            "NODE_OPTIONS",
            string.concat("--import=file://", vm.projectRoot(), "/test/fixtures/launch/metadata-preload.mjs")
        );
        vm.setEnv("EODHD_API_KEY", "launch-test");
        try this.generateAndAssert() {
            _cleanup();
        } catch (bytes memory reason) {
            _cleanup();
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    function generateAndAssert() external {
        GenerateMetadata script = new GenerateMetadata();
        script.run("rai3577ffitest", "equity", "US0000000002");
        string memory equity = vm.readFile(OUTPUT);
        assertEq(vm.parseJsonString(equity, ".primary_ticker"), "RAI3577FFITEST");
        assertEq(vm.parseJsonString(equity, ".asset_type"), "Equity");
        assertEq(vm.parseJsonString(equity, ".isin"), "US0000000002");
        assertEq(vm.parseJsonString(equity, ".ipo_date"), "2020-01-02");

        script.run("rai3577ffitest", "", "");
        string memory etf = vm.readFile(OUTPUT);
        assertEq(vm.parseJsonString(etf, ".asset_type"), "ETF");
        assertEq(vm.parseJsonString(etf, ".isin"), "US0000000001");
        assertEq(vm.parseJsonString(etf, ".inception_date"), "2020-01-02");
        assertEq(vm.parseJsonString(etf, ".category"), "Test category");
        assertEq(vm.parseJsonString(etf, ".country.iso"), "US");
        assertEq(vm.parseJsonString(etf, ".currency.code"), "USD");
        assertEq(vm.parseJsonString(etf, ".tokenised_issuer.name"), "S1 Issuer");

        vm.expectRevert();
        script.run("RAI3577EMPTY", "", "");
    }

    function _cleanup() internal {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "-e";
        cmd[2] = "require('node:fs').rmSync(process.argv[1], {force:true})";
        cmd[3] = OUTPUT;
        vm.ffi(cmd);
    }
}
