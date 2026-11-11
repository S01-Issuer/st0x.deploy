// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";

import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title WorkflowChoicesTest
/// @notice The `run-script` and `manual-broadcast` dispatch choices name existing scripts and the deploy networks, and
/// every script is offered by one of them unless it is history-only.
contract WorkflowChoicesTest is Test {
    string internal constant RUN_SCRIPT = ".github/workflows/run-script.yaml";
    string internal constant MANUAL_BROADCAST = ".github/workflows/manual-broadcast.yaml";

    /// The scripts whose `run()` refuses because the V5 backfill writes their root-line record.
    function historyOnly() internal pure returns (string[] memory) {
        string[] memory scripts = new string[](5);
        scripts[0] = "20260813-execute-timelock-operations";
        scripts[1] = "20260813-timelock-rehearsal-cancel";
        scripts[2] = "20260813-timelock-rehearsal-schedule";
        scripts[3] = "20261006-grant-eu-authoriser-roles";
        scripts[4] = "20261006-grant-orchestrator-emergency";
        return scripts;
    }

    function indentation(string memory line) internal pure returns (uint256) {
        bytes memory raw = bytes(line);
        uint256 i = 0;
        while (i < raw.length && raw[i] == " ") {
            i++;
        }
        return i;
    }

    function isInert(string memory line) internal pure returns (bool) {
        bytes memory trimmed = bytes(vm.trim(line));
        return trimmed.length == 0 || trimmed[0] == "#";
    }

    /// `value` without a trailing ` # ...` comment and without one pair of enclosing single or double quotes.
    function unquote(string memory value) internal pure returns (string memory) {
        string[] memory commented = vm.split(value, " #");
        bytes memory raw = bytes(vm.trim(commented[0]));
        bool single = raw.length >= 2 && raw[0] == "'" && raw[raw.length - 1] == "'";
        bool double = raw.length >= 2 && raw[0] == '"' && raw[raw.length - 1] == '"';
        if (single || double) {
            bytes memory inner = new bytes(raw.length - 2);
            for (uint256 i = 0; i < inner.length; i++) {
                inner[i] = raw[i + 1];
            }
            return string(inner);
        }
        return string(raw);
    }

    /// The `options` of `input` in `workflow`.
    function choices(string memory workflow, string memory input) internal view returns (string[] memory) {
        return choicesIn(workflow, vm.readFile(workflow), input);
    }

    /// The index of the line of `input` directly under the first `inputs:` of `lines`, read from `workflow`.
    function inputLine(string memory workflow, string[] memory lines, string memory input)
        internal
        pure
        returns (uint256)
    {
        uint256 i = 0;
        while (i < lines.length && keccak256(bytes(vm.trim(lines[i]))) != keccak256("inputs:")) {
            i++;
        }
        assertTrue(i < lines.length, string.concat(workflow, " has no inputs"));
        uint256 inputsIndentation = indentation(lines[i]);
        i++;
        bytes32 header = keccak256(bytes(string.concat(input, ":")));
        uint256 childIndentation = 0;
        bool matched = false;
        for (; i < lines.length; i++) {
            if (isInert(lines[i])) {
                continue;
            }
            if (indentation(lines[i]) <= inputsIndentation) {
                break;
            }
            if (childIndentation == 0) {
                childIndentation = indentation(lines[i]);
            }
            if (indentation(lines[i]) == childIndentation && keccak256(bytes(vm.trim(lines[i]))) == header) {
                matched = true;
                break;
            }
        }
        assertTrue(matched, string.concat(workflow, " has no input ", input));
        return i;
    }

    /// The `options` of `input` in the workflow text `text`, read from `workflow`.
    function choicesIn(string memory workflow, string memory text, string memory input)
        internal
        pure
        returns (string[] memory)
    {
        string[] memory lines = vm.split(text, "\n");
        uint256 i = inputLine(workflow, lines, input);
        uint256 inputIndentation = indentation(lines[i]);
        i++;
        while (i < lines.length && keccak256(bytes(vm.trim(lines[i]))) != keccak256("options:")) {
            assertTrue(isInert(lines[i]) || indentation(lines[i]) > inputIndentation, "options outside the input");
            i++;
        }
        assertTrue(i < lines.length, string.concat(workflow, " input ", input, " has no options"));
        uint256 optionsIndentation = indentation(lines[i]);
        i++;
        string[] memory found = new string[](lines.length - i);
        uint256 count = 0;
        for (; i < lines.length; i++) {
            if (isInert(lines[i])) {
                continue;
            }
            if (indentation(lines[i]) <= optionsIndentation) {
                break;
            }
            bytes memory item = bytes(vm.trim(lines[i]));
            assertTrue(
                item.length >= 2 && item[0] == "-" && item[1] == " ",
                string.concat(workflow, " input ", input, " has a line that is not a choice")
            );
            bytes memory choice = new bytes(item.length - 2);
            for (uint256 j = 0; j < choice.length; j++) {
                choice[j] = item[j + 2];
            }
            found[count] = unquote(vm.trim(string(choice)));
            count++;
        }
        assertTrue(count > 0, string.concat(workflow, " input ", input, " lists nothing"));
        assembly ("memory-safe") {
            mstore(found, count)
        }
        return found;
    }

    function contains(string[] memory list, string memory value) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (keccak256(bytes(list[i])) == keccak256(bytes(value))) {
                return true;
            }
        }
        return false;
    }

    function assertScriptChoices(string memory workflow) internal view {
        assertScripts(workflow, choices(workflow, "script"));
    }

    /// Each of `scripts` is a script under `script/`, once, and not history-only.
    function assertScripts(string memory workflow, string[] memory scripts) internal view {
        for (uint256 i = 0; i < scripts.length; i++) {
            assertTrue(
                vm.exists(string.concat("script/", scripts[i], ".s.sol")),
                string.concat(workflow, " lists ", scripts[i])
            );
            assertFalse(
                contains(historyOnly(), scripts[i]), string.concat(workflow, " lists history-only ", scripts[i])
            );
            for (uint256 j = i + 1; j < scripts.length; j++) {
                assertTrue(
                    keccak256(bytes(scripts[i])) != keccak256(bytes(scripts[j])),
                    string.concat(workflow, " repeats ", scripts[i])
                );
            }
        }
    }

    function assertNetworkChoices(string memory workflow) internal view {
        assertNetworks(workflow, choices(workflow, "network"));
    }

    /// `networks` are exactly the deploy networks.
    function assertNetworks(string memory workflow, string[] memory networks) internal pure {
        string[] memory deployed = LibStoxDeployNetworks.deploymentNetworks();
        assertEq(networks.length, deployed.length, string.concat(workflow, " network count"));
        for (uint256 i = 0; i < deployed.length; i++) {
            assertTrue(contains(networks, deployed[i]), string.concat(workflow, " misses ", deployed[i]));
        }
    }

    /// Each `run-script` choice is a script under `script/`, once, and not history-only.
    function testRunScriptChoicesAreScripts() external view {
        assertScriptChoices(RUN_SCRIPT);
    }

    /// Each `manual-broadcast` choice is a script under `script/`, once, and not history-only.
    function testManualBroadcastChoicesAreScripts() external view {
        assertScriptChoices(MANUAL_BROADCAST);
    }

    /// Both workflows offer exactly the deploy networks.
    function testNetworkChoicesAreTheDeployNetworks() external view {
        assertNetworkChoices(RUN_SCRIPT);
        assertNetworkChoices(MANUAL_BROADCAST);
    }

    /// Every script under `script/` is offered by a workflow, or is history-only and exists.
    function testEveryScriptIsDispatchable() external view {
        string[] memory names = scriptNames(vm.readDir("script", 2));
        assertOffered(names, choices(RUN_SCRIPT, "script"), choices(MANUAL_BROADCAST, "script"));
        assertHistoryOnlyExists(historyOnly());
    }

    /// The names of the `.s.sol` scripts among `entries`, each directly under `script/`; there is at least one.
    function scriptNames(Vm.DirEntry[] memory entries) internal pure returns (string[] memory) {
        string[] memory names = new string[](entries.length);
        uint256 count = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            string memory path = entries[i].path;
            if (!vm.contains(path, ".s.sol")) {
                continue;
            }
            assertTrue(entries[i].depth == 1, string.concat("nested script ", path));
            string[] memory parts = vm.split(path, "/");
            names[count] = vm.replace(parts[parts.length - 1], ".s.sol", "");
            count++;
        }
        assertTrue(count > 0, "no scripts");
        assembly ("memory-safe") {
            mstore(names, count)
        }
        return names;
    }

    /// Each of `history` is a script under `script/`.
    function assertHistoryOnlyExists(string[] memory history) internal view {
        for (uint256 i = 0; i < history.length; i++) {
            assertTrue(
                vm.exists(string.concat("script/", history[i], ".s.sol")), string.concat("no script ", history[i])
            );
        }
    }

    /// Each of `names` is in `run` or `broadcast`, or is history-only.
    function assertOffered(string[] memory names, string[] memory run, string[] memory broadcast) internal pure {
        for (uint256 i = 0; i < names.length; i++) {
            assertTrue(
                contains(run, names[i]) || contains(broadcast, names[i]) || contains(historyOnly(), names[i]),
                string.concat("no workflow offers ", names[i])
            );
        }
    }

    function externalChoicesIn(string memory text, string memory input) external pure returns (string[] memory) {
        return choicesIn("fixture", text, input);
    }

    function externalAssertScripts(string[] memory scripts) external view {
        assertScripts("fixture", scripts);
    }

    function externalAssertNetworks(string[] memory networks) external pure {
        assertNetworks("fixture", networks);
    }

    function externalAssertOffered(string[] memory names, string[] memory run, string[] memory broadcast)
        external
        pure
    {
        assertOffered(names, run, broadcast);
    }

    function one(string memory value) internal pure returns (string[] memory) {
        string[] memory list = new string[](1);
        list[0] = value;
        return list;
    }

    /// The parser reads an input's list, skips comments, unquotes, and stops at the next key.
    function testChoicesReadTheInputsList() external view {
        string[] memory found = this.externalChoicesIn(
            "on:\n  workflow_dispatch:\n    inputs:\n      network:\n        type: choice\n        options:\n"
            "          # a comment\n          - 'base'\n\n          - bsc\n      sig:\n        options:\n          - run()\n",
            "network"
        );
        assertEq(found.length, 2, "two networks");
        assertEq(found[0], "base", "unquoted");
        assertEq(found[1], "bsc", "after a blank line");
    }

    /// Double quotes and a trailing comment are stripped from a choice.
    function testChoicesStripDoubleQuotesAndComments() external view {
        string[] memory found = this.externalChoicesIn(
            "inputs:\n  script:\n    options:\n      - \"20261030-backfill-migration-registry-v5\"\n"
            "      - 20261021-execute-underlying-naming # the executor\n  network:\n",
            "script"
        );
        assertEq(found.length, 2, "two choices");
        assertEq(found[0], "20261030-backfill-migration-registry-v5", "double quotes");
        assertEq(found[1], "20261021-execute-underlying-naming", "comment");
    }

    /// A line inside the options block that is not a choice is refused rather than ending the list.
    function testChoicesRefuseAStrayLine() external {
        vm.expectRevert(bytes("fixture input script has a line that is not a choice"));
        this.externalChoicesIn("inputs:\n  script:\n    options:\n      - a\n        continued\n      - b\n", "script");
    }

    /// An input without options, or without its key, is refused.
    function testChoicesRefuseAMissingList() external {
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn("inputs:\n  network:\n    options:\n      - base\n", "script");
        vm.expectRevert(bytes("fixture input script has no options"));
        this.externalChoicesIn("inputs:\n  script:\n    type: choice\n", "script");
        vm.expectRevert(bytes("options outside the input"));
        this.externalChoicesIn("inputs:\n  script:\n  network:\n    options:\n      - base\n", "script");
        vm.expectRevert(bytes("fixture input script lists nothing"));
        this.externalChoicesIn("inputs:\n  script:\n    options:\n  network: x\n", "script");
    }

    /// A choice with no script, a repeated choice, and a history-only choice are refused.
    function testScriptChoicesRefuseABadEntry() external {
        vm.expectRevert(bytes("fixture lists 29990101-no-such-script"));
        this.externalAssertScripts(one("29990101-no-such-script"));
        string[] memory repeated = new string[](2);
        repeated[0] = "20261030-backfill-migration-registry-v5";
        repeated[1] = "20261030-backfill-migration-registry-v5";
        vm.expectRevert(bytes("fixture repeats 20261030-backfill-migration-registry-v5"));
        this.externalAssertScripts(repeated);
        vm.expectRevert(bytes("fixture lists history-only 20261006-grant-orchestrator-emergency"));
        this.externalAssertScripts(one("20261006-grant-orchestrator-emergency"));
    }

    /// A missing or extra network is refused.
    function testNetworkChoicesRefuseAnotherSet() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        networks[4] = "arbitrum";
        vm.expectRevert(bytes("fixture misses bsc"));
        this.externalAssertNetworks(networks);
        vm.expectRevert(bytes("fixture network count: 1 != 5"));
        this.externalAssertNetworks(one("base"));
    }

    /// The history-only list is exactly the scripts whose test extends `BackfilledHistoryScriptTest`, which proves
    /// their `run()` refuses on every chain.
    function testHistoryOnlyIsTheBackfilledHistoryScripts() external view {
        Vm.DirEntry[] memory entries = vm.readDir("test/script", 1);
        string[] memory paths = new string[](entries.length);
        string[] memory texts = new string[](entries.length);
        for (uint256 i = 0; i < entries.length; i++) {
            paths[i] = entries[i].path;
            texts[i] = entries[i].isDir ? "" : vm.readFile(entries[i].path);
        }
        assertHistoryOnlyIs(markedScripts(paths, texts), historyOnly());
    }

    /// A script refuses with a `RecordedByBackfill` error exactly when it is history-only.
    function testHistoryOnlyIsEveryRefusingScript() external view {
        string[] memory names = scriptNames(vm.readDir("script", 2));
        string[] memory texts = new string[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            texts[i] = vm.readFile(string.concat("script/", names[i], ".s.sol"));
        }
        assertRefusingIsHistoryOnly(names, texts, historyOnly());
    }

    /// The script `names[i]`, with source `texts[i]`, reverts with a `RecordedByBackfill(block.chainid)` error exactly
    /// when it is in `history`.
    function assertRefusingIsHistoryOnly(string[] memory names, string[] memory texts, string[] memory history)
        internal
        pure
    {
        for (uint256 i = 0; i < names.length; i++) {
            bool refuses = vm.contains(texts[i], "RecordedByBackfill(block.chainid)");
            bool listed = contains(history, names[i]);
            assertTrue(!refuses || listed, string.concat("refuses but not history-only: ", names[i]));
            assertTrue(refuses || !listed, string.concat("history-only but runs: ", names[i]));
        }
    }

    /// `history` is exactly `marked`, and `marked` names each script once.
    function assertHistoryOnlyIs(string[] memory marked, string[] memory history) internal pure {
        for (uint256 i = 0; i < marked.length; i++) {
            assertTrue(contains(history, marked[i]), string.concat("history-only but not listed: ", marked[i]));
            for (uint256 j = i + 1; j < marked.length; j++) {
                assertTrue(
                    keccak256(bytes(marked[i])) != keccak256(bytes(marked[j])),
                    string.concat("two history tests for ", marked[i])
                );
            }
        }
        for (uint256 i = 0; i < history.length; i++) {
            assertTrue(contains(marked, history[i]), string.concat("listed but no history test: ", history[i]));
        }
    }

    /// The import that marks a test as a `BackfilledHistoryScriptTest`, built in two parts so this file does not carry
    /// it.
    function historyMarker() internal pure returns (string memory) {
        return string.concat("../lib/Backfilled", "HistoryScriptTest.sol");
    }

    /// The scripts whose test, at `paths[i]` with text `texts[i]`, imports `BackfilledHistoryScriptTest`, named by the
    /// test file's name up to its first `.`.
    function markedScripts(string[] memory paths, string[] memory texts) internal pure returns (string[] memory) {
        string[] memory marked = new string[](paths.length);
        uint256 count = 0;
        for (uint256 i = 0; i < paths.length; i++) {
            if (!vm.contains(paths[i], ".t.sol") || !vm.contains(texts[i], historyMarker())) {
                continue;
            }
            string[] memory parts = vm.split(paths[i], "/");
            marked[count] = vm.split(parts[parts.length - 1], ".")[0];
            count++;
        }
        assembly ("memory-safe") {
            mstore(marked, count)
        }
        return marked;
    }

    function externalScriptNames(Vm.DirEntry[] memory entries) external pure returns (string[] memory) {
        return scriptNames(entries);
    }

    function externalAssertHistoryOnlyExists(string[] memory history) external view {
        assertHistoryOnlyExists(history);
    }

    function externalAssertHistoryOnlyIs(string[] memory marked, string[] memory history) external pure {
        assertHistoryOnlyIs(marked, history);
    }

    /// The script list refuses no scripts and a script nested under `script/`.
    function testScriptNamesRefuseNoScriptsAndNestedScripts() external {
        Vm.DirEntry[] memory entries = new Vm.DirEntry[](2);
        entries[0] =
            VmSafe.DirEntry({errorMessage: "", path: "script/Build.sol", depth: 1, isDir: false, isSymlink: false});
        entries[1] = VmSafe.DirEntry({
            errorMessage: "", path: "script/20990101-top.s.sol", depth: 1, isDir: false, isSymlink: false
        });
        string[] memory names = this.externalScriptNames(entries);
        assertEq(names.length, 1, "one script");
        assertEq(names[0], "20990101-top", "its name");
        Vm.DirEntry[] memory none = new Vm.DirEntry[](1);
        none[0] = entries[0];
        vm.expectRevert(bytes("no scripts"));
        this.externalScriptNames(none);
        entries[1] = VmSafe.DirEntry({
            errorMessage: "", path: "script/x/20990101-nested.s.sol", depth: 2, isDir: false, isSymlink: false
        });
        vm.expectRevert(bytes("nested script script/x/20990101-nested.s.sol"));
        this.externalScriptNames(entries);
    }

    /// A history-only name with no script is refused.
    function testHistoryOnlyNameMustExist() external {
        this.externalAssertHistoryOnlyExists(historyOnly());
        vm.expectRevert(bytes("no script 29990101-gone"));
        this.externalAssertHistoryOnlyExists(one("29990101-gone"));
    }

    /// A marked script missing from the list, and a listed script that is not marked, are refused.
    function testHistoryOnlyMustMatchTheMarkedScripts() external {
        this.externalAssertHistoryOnlyIs(one("a"), one("a"));
        vm.expectRevert(bytes("history-only but not listed: b"));
        this.externalAssertHistoryOnlyIs(one("b"), one("a"));
        string[] memory two = new string[](2);
        two[0] = "a";
        two[1] = "b";
        vm.expectRevert(bytes("listed but no history test: b"));
        this.externalAssertHistoryOnlyIs(one("a"), two);
    }

    function externalMarkedScripts(string[] memory paths, string[] memory texts)
        external
        pure
        returns (string[] memory)
    {
        return markedScripts(paths, texts);
    }

    /// A duplicate marked name cannot hide a listed name that no test marks.
    function testHistoryOnlyRefusesADuplicateMark() external {
        string[] memory marked = new string[](2);
        marked[0] = "a";
        marked[1] = "a";
        vm.expectRevert(bytes("two history tests for a"));
        this.externalAssertHistoryOnlyIs(marked, one("a"));
        string[] memory listed = new string[](2);
        listed[0] = "a";
        listed[1] = "b";
        vm.expectRevert(bytes("two history tests for a"));
        this.externalAssertHistoryOnlyIs(marked, listed);
    }

    /// Only a `.t.sol` that imports the marker counts, named up to its first `.`.
    function testMarkedScriptsReadTheImport() external view {
        string[] memory paths = new string[](4);
        string[] memory texts = new string[](4);
        paths[0] = "test/script/20990101-a.history.t.sol";
        texts[0] = string.concat('import {X} from "', historyMarker(), '";');
        paths[1] = "test/script/20990101-b.t.sol";
        texts[1] = "contract B {}";
        paths[2] = "test/script/Harness.sol";
        texts[2] = string.concat('import {X} from "', historyMarker(), '";');
        paths[3] = "test/script/20990101-c.t.sol";
        texts[3] = string.concat('import {X, Y} from "', historyMarker(), '";');
        string[] memory marked = this.externalMarkedScripts(paths, texts);
        assertEq(marked.length, 2, "two marked");
        assertEq(marked[0], "20990101-a", "name up to the first dot");
        assertEq(marked[1], "20990101-c", "second marked");
    }

    /// The list ends at a key level with `options:`, and a trailing comment is stripped after any spaces.
    function testChoicesStopAtASiblingKeyAndStripSpacedComments() external view {
        string[] memory found = this.externalChoicesIn(
            "inputs:\n  network:\n    options:\n      - base  # two spaces\n      - 'bsc'  # quoted\n    default: base\n"
            "  sig: x\n",
            "network"
        );
        assertEq(found.length, 2, "two networks");
        assertEq(found[0], "base", "comment after two spaces");
        assertEq(found[1], "bsc", "quoted, comment after two spaces");
    }

    /// A line in the options block that does not start with a dash is refused.
    function testChoicesRefuseALineWithoutADash() external {
        vm.expectRevert(bytes("fixture input network has a line that is not a choice"));
        this.externalChoicesIn("inputs:\n  network:\n    options:\n      - base\n      x bsc\n", "network");
    }

    /// Only an input directly under the first `inputs:` is read, not a key of the same name elsewhere.
    function testChoicesReadTheDispatchInput() external view {
        string[] memory found = this.externalChoicesIn(
            "jobs:\n  script:\n    options:\n      - wrong\non:\n  workflow_dispatch:\n    inputs:\n      script:\n"
            "        options:\n          - right\n",
            "script"
        );
        assertEq(found.length, 1, "one choice");
        assertEq(found[0], "right", "the dispatch input");
    }

    /// A workflow without `inputs:`, or whose inputs end before the input, is refused.
    function testChoicesRefuseAnInputOutsideInputs() external {
        vm.expectRevert(bytes("fixture has no inputs"));
        this.externalChoicesIn("jobs:\n  script:\n    options:\n      - a\n", "script");
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn(
            "on:\n  inputs:\n    network:\n      options:\n        - base\njobs:\n  script:\n", "script"
        );
    }

    function externalAssertRefusingIsHistoryOnly(string[] memory names, string[] memory texts, string[] memory history)
        external
        pure
    {
        assertRefusingIsHistoryOnly(names, texts, history);
    }

    /// A refusing script must be history-only, and a history-only script must refuse; an error declaration alone is
    /// not a refusal.
    function testRefusingScriptsAreExactlyHistoryOnly() external {
        string[] memory texts = new string[](1);
        texts[0] = "error XRecordedByBackfill(uint256 chainId);\nrevert XRecordedByBackfill(block.chainid);";
        this.externalAssertRefusingIsHistoryOnly(one("a"), texts, one("a"));
        vm.expectRevert(bytes("refuses but not history-only: a"));
        this.externalAssertRefusingIsHistoryOnly(one("a"), texts, new string[](0));
        texts[0] = "error XRecordedByBackfill(uint256 chainId);";
        vm.expectRevert(bytes("history-only but runs: a"));
        this.externalAssertRefusingIsHistoryOnly(one("a"), texts, one("a"));
    }

    /// Only the `../lib/` import of `BackfilledHistoryScriptTest.sol` marks a test, not the file name from another path.
    function testMarkedScriptsNeedTheLibImport() external view {
        string[] memory paths = new string[](2);
        string[] memory texts = new string[](2);
        paths[0] = "test/script/20990101-a.t.sol";
        texts[0] = 'import {BackfilledHistoryScriptTest} from "./Backfilled' 'HistoryScriptTest.sol";';
        paths[1] = "test/script/20990101-b.t.sol";
        texts[1] = 'import {BackfilledHistoryScriptTest} from "../lib/Backfilled' 'HistoryScriptTest.sol";';
        string[] memory marked = this.externalMarkedScripts(paths, texts);
        assertEq(marked.length, 1, "one marked");
        assertEq(marked[0], "20990101-b", "the lib import");
    }

    /// The input search skips blank lines and comments, and ends at the first key at or above the level of `inputs:`.
    function testChoicesSearchOnlyTheInputsBlock() external {
        string[] memory found = this.externalChoicesIn(
            "on:\n  workflow_dispatch:\n    inputs:\n\n# a comment\n      script:\n        options:\n          - right\n",
            "script"
        );
        assertEq(found.length, 1, "one choice");
        assertEq(found[0], "right", "past a blank line and a comment");
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn(
            "on:\n  workflow_call:\n    inputs:\n      network:\n        options:\n          - base\n"
            "    secrets:\n      script:\n        options:\n          - wrong\n",
            "script"
        );
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn(
            "on:\n  workflow_dispatch:\n    inputs:\n      network:\n        options:\n          - base\n"
            "  workflow_call:\n    inputs:\n      script:\n        options:\n          - wrong\n",
            "script"
        );
    }

    /// A key of the input's name that ends the `inputs:` block, or follows an empty block, is not the input.
    function testChoicesRefuseTheKeyThatEndsTheBlock() external {
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn(
            "on:\n  workflow_dispatch:\n    inputs:\n      network:\n        options:\n          - base\n"
            "    script:\n      options:\n        - wrong\n",
            "script"
        );
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn(
            "inputs:\n  network:\n    options:\n      - base\nscript:\n  options:\n    - wrong\n", "script"
        );
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn("inputs:\nscript:\n  options:\n    - wrong\n", "script");
    }

    /// A key of the input's name nested under another input is not the input.
    function testChoicesReadOnlyAChildOfInputs() external {
        vm.expectRevert(bytes("fixture has no input script"));
        this.externalChoicesIn("inputs:\n  network:\n    script:\n      options:\n        - x\n", "script");
    }

    /// The parser trims an item's value, keeps an unterminated quote, and refuses an item that is not `- <value>`.
    function testChoicesReadEdgeItems() external {
        string[] memory found = this.externalChoicesIn(
            "inputs:\n  network:\n    options:\n      -   base\n      - 'bsc\n      - \"eth\n  sig: x\n", "network"
        );
        assertEq(found.length, 3, "three items");
        assertEq(found[0], "base", "trimmed");
        assertEq(found[1], "'bsc", "unterminated single quote kept");
        assertEq(found[2], "\"eth", "unterminated double quote kept");
        vm.expectRevert(bytes("fixture input network has a line that is not a choice"));
        this.externalChoicesIn("inputs:\n  network:\n    options:\n      - base\n      -xethereum\n", "network");
        vm.expectRevert(bytes("fixture input network has a line that is not a choice"));
        this.externalChoicesIn("inputs:\n  network:\n    options:\n      - base\n      -\n      - bsc\n", "network");
    }

    /// A script no workflow offers is refused unless it is history-only.
    function testAScriptNoWorkflowOffersIsRefused() external {
        string[] memory none = new string[](0);
        this.externalAssertOffered(one("20260813-execute-timelock-operations"), none, none);
        this.externalAssertOffered(
            one("20261030-backfill-migration-registry-v5"), one("20261030-backfill-migration-registry-v5"), none
        );
        this.externalAssertOffered(
            one("20261021-execute-underlying-naming"), none, one("20261021-execute-underlying-naming")
        );
        vm.expectRevert(bytes("no workflow offers 20261030-backfill-migration-registry-v5"));
        this.externalAssertOffered(one("20261030-backfill-migration-registry-v5"), none, none);
    }
}
