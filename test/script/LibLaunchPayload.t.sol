// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibLaunchPayload, LaunchPayloads, MissingCid} from "../../script/lib/LibLaunchPayload.sol";
import {LibRainMeta} from "../../src/lib/LibRainMeta.sol";

contract LibLaunchPayloadTest is Test {
    function frame(bytes memory out) external pure returns (LaunchPayloads memory) {
        return LibLaunchPayload.frame(out);
    }

    function testFrameRefusesAnEmptyCid() external {
        vm.expectRevert(MissingCid.selector);
        this.frame(abi.encode(hex"01", "", hex"02", "bafkmeta"));
        vm.expectRevert(MissingCid.selector);
        this.frame(abi.encode(hex"01", "bafkschema", hex"02", ""));
    }

    function testFrameCarriesEachCidInItsDocument() external view {
        LaunchPayloads memory payloads = this.frame(abi.encode(hex"01", "bafkschema", hex"02", "bafkmeta"));
        assertEq(payloads.schemaMeta, LibRainMeta.encode(hex"01", "bafkschema"));
        assertEq(payloads.schemaCid, "bafkschema");
        assertEq(payloads.metadataMeta, LibRainMeta.encode(hex"02", "bafkmeta"));
        assertEq(payloads.metadataCid, "bafkmeta");
    }
}
