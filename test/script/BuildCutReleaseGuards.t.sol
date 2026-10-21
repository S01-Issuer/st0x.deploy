// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {NonMonotonicRelease, SnapshotAlreadyFrozen} from "rain-deploy-0.1.18/src/lib/LibRainDeploySnapshot.sol";
import {BuildCutReleaseGuardsHarness} from "./BuildCutReleaseGuardsHarness.sol";

contract BuildCutReleaseGuardsTest is Test {
    BuildCutReleaseGuardsHarness internal build = new BuildCutReleaseGuardsHarness();

    function record(string memory name, string[] memory dirs) internal returns (string memory) {
        string memory root = string.concat("out/test-build-cut-release/", name);
        if (vm.exists(root)) vm.removeDir(root, true);
        vm.createDir(root, true);
        for (uint256 i = 0; i < dirs.length; i++) {
            vm.createDir(string.concat(root, "/", dirs[i]), true);
        }
        return root;
    }

    function dirs3(string memory a, string memory b, string memory c) internal pure returns (string[] memory d) {
        d = new string[](3);
        d[0] = a;
        d[1] = b;
        d[2] = c;
    }

    function testCutReleaseRefusesAnAlreadyFrozenTag() external {
        string memory root = record("frozen", dirs3("0_1_1", "0_1_30", "candidate"));
        vm.expectRevert(
            abi.encodeWithSelector(SnapshotAlreadyFrozen.selector, "0_1_30", string.concat(root, "/0_1_30"))
        );
        build.checkReleaseIsNewExternal(root, "0_1_30");
    }

    function testCutReleaseRefusesAnOlderFrozenTag() external {
        string memory root = record("older-frozen", dirs3("0_1_1", "0_1_30", "candidate"));
        vm.expectRevert(abi.encodeWithSelector(SnapshotAlreadyFrozen.selector, "0_1_1", string.concat(root, "/0_1_1")));
        build.checkReleaseIsNewExternal(root, "0_1_1");
    }

    function testCutReleaseRefusesATagBelowTheNewestRelease() external {
        string memory root = record("below-newest", dirs3("0_1_1", "0_1_30", "candidate"));
        vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, "0_1_29", "0_1_30"));
        build.checkReleaseIsNewExternal(root, "0_1_29");
    }

    function testCutReleaseRefusesASpellingOfTheNewestRelease() external {
        string memory root = record("respelled-newest", dirs3("0_1_1", "0_1_30", "candidate"));
        vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, "0_1_030", "0_1_30"));
        build.checkReleaseIsNewExternal(root, "0_1_030");
    }

    function testCutReleaseOrdersReleasesNumerically() external {
        string memory root = record("numeric-order", dirs3("0_1_30", "0_1_9", "candidate"));
        vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, "0_1_10", "0_1_30"));
        build.checkReleaseIsNewExternal(root, "0_1_10");
    }

    function testCutReleaseComparesEveryVersionComponent() external {
        string memory root = record("components", dirs3("0_1_30", "0_2_0", "candidate"));
        vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, "0_1_31", "0_2_0"));
        build.checkReleaseIsNewExternal(root, "0_1_31");
    }

    function testCutReleaseAcceptsATagAboveTheNewestRelease() external {
        string memory root = record("above-newest", dirs3("0_1_1", "0_1_30", "candidate"));
        assertEq(build.checkReleaseIsNewExternal(root, "0_1_31"), string.concat(root, "/0_1_31"));
    }

    function testCutReleaseAcceptsAFirstRelease() external {
        string[] memory onlyCandidate = new string[](1);
        onlyCandidate[0] = "candidate";
        string memory root = record("first-release", onlyCandidate);
        assertEq(build.checkReleaseIsNewExternal(root, "0_0_1"), string.concat(root, "/0_0_1"));
    }
}
