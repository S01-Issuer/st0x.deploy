// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LaunchBaseTokens, FixedCidsIncomplete} from "../script/20261020-launch-base-tokens.s.sol";

/// @notice `prepare` marks a payload holding test CIDs `fixed-cids`, the only
/// thing that keeps the broadcasting stages from publishing it, and refuses a
/// half-set pair.
contract LaunchBaseTokensPrepareFfiTest is Test {
    function testPrepareLabelsFixedCids() external {
        LaunchBaseTokens script = new LaunchBaseTokens();
        string memory dir = "out/test-ffi-launch-prepare";
        if (vm.exists(dir)) vm.removeDir(dir, true);
        vm.createDir(dir, true);
        LaunchBaseTokens.LaunchPaths memory at = LaunchBaseTokens.LaunchPaths({
            plan: string.concat(dir, "/plan.json"),
            stageDir: string.concat(dir, "/stages"),
            ledger: string.concat(dir, "/launches.json"),
            allowlist: "launch/allowlist.json"
        });
        vm.writeFile(at.ledger, "[]\n");
        LaunchBaseTokens.PlanInputs memory inputs = LaunchBaseTokens.PlanInputs({
            ledger: at.ledger,
            allowlist: at.allowlist,
            pins: "launch/dedicated-authorisers.json"
        });
        string[] memory files = new string[](1);
        files[0] = "launch/metadata/dis.json";
        script.writePlan(
            script.planFiles(files, script.planContext(inputs.ledger, inputs.allowlist, inputs.pins, 1792079467)),
            inputs,
            1792079467,
            at.plan
        );

        script.prepareStage(at, "tDIS", "bafkschema", "bafkmeta");
        assertEq(vm.parseJsonString(vm.readFile(script.stageFile(at, "tDIS", "payloads")), ".mode"), "fixed-cids");
        vm.expectRevert(abi.encodeWithSelector(FixedCidsIncomplete.selector, "tDIS"));
        script.prepareStage(at, "tDIS", "bafkschema", "");
        vm.expectRevert(abi.encodeWithSelector(FixedCidsIncomplete.selector, "tDIS"));
        script.prepareStage(at, "tDIS", "", "bafkmeta");
    }
}
