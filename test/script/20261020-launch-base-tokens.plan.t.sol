// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    LaunchBaseTokens,
    LaunchPlanInvalid,
    DuplicateSymbol,
    LaunchInputOutsideOut
} from "../../script/20261020-launch-base-tokens.s.sol";
import {LaunchFilePlanner} from "../../script/LaunchFilePlanner.sol";
import {LibLaunchInputs} from "../../script/lib/LibLaunchInputs.sol";
import {
    LibLaunchPlan,
    PlanContext,
    DedicatedPin,
    TokenPlan,
    AssetType,
    UnsupportedAssetType,
    InvalidCounterparties,
    LaunchMetadata,
    MissingPrimaryTicker,
    InvalidTicker,
    MissingName,
    NameIsTicker,
    UnicodeWhitespaceInName,
    ControlCharacterInName,
    InvalidCountryIso,
    InvalidIsin,
    OwnerNotAllowlisted,
    DedicatedPinWrongChain,
    DedicatedAuthoriserUnset,
    DedicatedAuthoriserIsShared,
    DedicatedMinterUnset,
    DedicatedDeployBlockUnset,
    DedicatedAuthoriserNotAllowlisted
} from "../../src/lib/LibLaunchPlan.sol";
import {LibUtcDate} from "../../src/lib/LibUtcDate.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";

/// @title LaunchBaseTokensPlanTest
/// @notice `plan()` and the input loader against the committed files under
/// `launch/`, which were copied from sft-ops: every outcome here is the one
/// sft-ops `cd-plan` gives for the same files.
contract LaunchBaseTokensPlanTest is Test {
    address constant SHARED = 0x315b16faa6eE413faBCa877d3851B3818369f0cD;
    address constant MINTER = 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C;
    uint256 constant NOW = 1787140800;

    LaunchBaseTokens internal script;

    function setUp() external {
        script = new LaunchBaseTokens();
    }

    function _committedContext() internal view returns (PlanContext memory) {
        return
            script.planContext(
                "launch/launches.json", "launch/allowlist.json", "launch/dedicated-authorisers.json", NOW
            );
    }

    function _metadataFiles() internal view returns (string[] memory files) {
        return _dirFiles("launch/metadata/", 2);
    }

    /// @dev `readDir` paths are absolute; each is returned as `dir` plus what
    /// follows `dir` in it.
    function _dirFiles(string memory dir, uint64 depth) internal view returns (string[] memory files) {
        Vm.DirEntry[] memory entries = vm.readDir(dir, depth);
        files = new string[](entries.length);
        for (uint256 i = 0; i < entries.length; i++) {
            files[i] = string.concat(dir, _after(entries[i].path, dir));
        }
    }

    function _after(string memory path, string memory marker) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(path);
        bytes memory markerBytes = bytes(marker);
        for (uint256 i = 0; i + markerBytes.length <= pathBytes.length; i++) {
            bool hit = true;
            for (uint256 j = 0; j < markerBytes.length; j++) {
                if (pathBytes[i + j] != markerBytes[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) {
                bytes memory rest = new bytes(pathBytes.length - i - markerBytes.length);
                for (uint256 k = 0; k < rest.length; k++) {
                    rest[k] = pathBytes[i + markerBytes.length + k];
                }
                return string(rest);
            }
        }
        return path;
    }

    /// @dev `launch/metadata/air.pa.json` names `tAIR.PA`: the symbol from the
    /// file name, upper-cased without `LibLaunchPlan`.
    function _symbolFromFileName(string memory file) internal pure returns (string memory) {
        bytes memory name = bytes(_after(file, "launch/metadata/"));
        bytes memory symbol = new bytes(name.length - bytes(".json").length + 1);
        symbol[0] = "t";
        for (uint256 i = 1; i < symbol.length; i++) {
            bytes1 char = name[i - 1];
            symbol[i] = char >= "a" && char <= "z" ? bytes1(uint8(char) - 32) : char;
        }
        return string(symbol);
    }

    /// @notice Every committed metadata file plans cleanly: a symbol already
    /// live or retired in the committed ledger skips, any other plans with no
    /// refusal, on the shared authoriser unless it is pinned. `published/` and
    /// its README are ignored.
    function testCommittedMetadataPlansAsSftOpsDoes() external {
        PlanContext memory ctx = _committedContext();
        string[] memory files = _metadataFiles();
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(files, ctx);
        assertEq(outcomes.length, files.length);
        uint256 ignored = 0;
        for (uint256 i = 0; i < outcomes.length; i++) {
            assertEq(outcomes[i].metadataFile, files[i]);
            assertEq(outcomes[i].ignored, !LibLaunchInputs.isMetadataFile(files[i]), files[i]);
            if (outcomes[i].ignored) {
                ignored++;
                continue;
            }
            assertFalse(outcomes[i].failed, outcomes[i].metadataFile);
            string memory symbol = _symbolFromFileName(outcomes[i].metadataFile);
            bool shipped = _shippedCaseInsensitive(ctx.shippedSymbols, symbol);
            assertEq(outcomes[i].skipped, shipped, outcomes[i].metadataFile);
            if (shipped) continue;
            assertEq(outcomes[i].plan.symbol, symbol);
            (bool pinned,) = LibLaunchPlan.findPin(ctx.pins, symbol);
            if (!pinned) assertEq(outcomes[i].plan.landingAuthoriser, SHARED);
        }
        assertGt(ignored, 0);
    }

    /// @notice A path that is not a deploy input is logged as ignored, never
    /// dropped silently; an empty entry is no path at all.
    function testPlanFilesReportsEveryIgnoredPath() external {
        string[] memory files = new string[](4);
        files[0] = "./launch/metadata/fgi.json";
        files[1] = "";
        files[2] = "launch//metadata/fgi.json";
        files[3] = "launch/metadata/wmt.json";
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(files, _committedContext());
        assertEq(outcomes.length, 3);
        assertTrue(outcomes[0].ignored);
        assertTrue(outcomes[1].ignored);
        assertFalse(outcomes[2].ignored);
        assertTrue(outcomes[2].skipped);
        (string[] memory lines, uint256 failures) = script.describeOutcomes(outcomes);
        assertEq(failures, 0);
        assertEq(lines.length, 4);
        assertEq(lines[0], "  ignore ./launch/metadata/fgi.json (not a launch/metadata/<name>.json file)");
        assertEq(lines[1], "  ignore launch//metadata/fgi.json (not a launch/metadata/<name>.json file)");
        assertEq(lines[2], "  skip  launch/metadata/wmt.json (already in the ledger)");
        assertEq(lines[3], "  nothing to deploy");
    }

    function _shippedCaseInsensitive(string[] memory shipped, string memory symbol) internal pure returns (bool) {
        for (uint256 i = 0; i < shipped.length; i++) {
            if (keccak256(bytes(vm.toLowercase(shipped[i]))) == keccak256(bytes(vm.toLowercase(symbol)))) return true;
        }
        return false;
    }

    /// @notice Every pin names the symbol of a committed metadata file, so a
    /// renamed or mistyped key cannot leave its token on the shared
    /// authoriser.
    function testEveryPinNamesACommittedMetadataFile() external view {
        string[] memory keys = vm.parseJsonKeys(vm.readFile("launch/dedicated-authorisers.json"), "$");
        string[] memory files = _metadataFiles();
        for (uint256 i = 0; i < keys.length; i++) {
            bool matched = false;
            for (uint256 j = 0; j < files.length && !matched; j++) {
                if (!LibLaunchInputs.isMetadataFile(files[j])) continue;
                matched = keccak256(bytes(vm.toLowercase(_symbolFromFileName(files[j]))))
                    == keccak256(bytes(vm.toLowercase(keys[i])));
            }
            assertTrue(matched, keys[i]);
        }
    }

    /// @notice sft-ops `cd-plan` on the metadata files and ledger frozen from
    /// sft-ops `ee39d0d` planned exactly tFGI and skipped the rest.
    function testCopiedSnapshotPlansOnlyFgi() external {
        string memory dir = "test/fixtures/launch/metadata-ee39d0d/";
        string[] memory files = _dirFiles(dir, 1);
        PlanContext memory ctx = script.planContext(
            "test/fixtures/launch/launches-ee39d0d.json",
            "launch/allowlist.json",
            "launch/dedicated-authorisers.json",
            NOW
        );
        LaunchFilePlanner planner = new LaunchFilePlanner();
        assertEq(files.length, 63);
        uint256 planned;
        for (uint256 i = 0; i < files.length; i++) {
            (bool skipped, TokenPlan memory tokenPlan) = planner.planFile(files[i], ctx);
            if (skipped) continue;
            planned++;
            assertEq(files[i], string.concat(dir, "fgi.json"));
            assertEq(tokenPlan.symbol, "tFGI");
            assertEq(tokenPlan.name, "FGI Industries Ltd. ST0x");
        }
        assertEq(planned, 1);
    }

    function testABatchCannotPlanOneSymbolTwice() external {
        vm.writeFile("out/test-launch-ledger-dup.json", "[]");
        string[] memory files = new string[](3);
        for (uint256 i = 0; i < files.length; i++) {
            files[i] = "launch/metadata/wmt.json";
        }
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(
            files,
            script.planContext(
                "out/test-launch-ledger-dup.json", "launch/allowlist.json", "launch/dedicated-authorisers.json", NOW
            )
        );
        assertFalse(outcomes[0].failed);
        for (uint256 i = 1; i < outcomes.length; i++) {
            assertTrue(outcomes[i].failed);
            assertEq(outcomes[i].failure, abi.encodeWithSelector(DuplicateSymbol.selector, "tWMT", files[0]));
        }
    }

    /// @notice The derivation reproduces the ledger name of every shipped
    /// token. Both sides are trimmed: tSGOV's on-chain name carries a stray
    /// leading space, a data defect in that deploy.
    function testDerivationMatchesTheShippedFleet() external view {
        string memory ledger = vm.readFile("launch/launches.json");
        string[] memory files = _metadataFiles();
        uint256 checked = 0;
        for (uint256 i = 0; i < files.length; i++) {
            if (!LibLaunchInputs.isMetadataFile(files[i])) continue;
            string memory json = vm.readFile(files[i]);
            string memory symbol =
                string.concat("t", LibLaunchPlan.toUpper(vm.parseJsonString(json, ".primary_ticker")));
            (bool found, string memory shippedName) = _liveName(ledger, symbol);
            if (!found) continue;
            checked++;
            string memory derived =
                string.concat(LibLaunchPlan.normaliseAdrName(vm.parseJsonString(json, ".name")), " ST0x");
            assertEq(LibLaunchPlan.trim(derived), LibLaunchPlan.trim(shippedName), symbol);
        }
        assertGt(checked, 50);
    }

    function _liveName(string memory ledger, string memory symbol)
        internal
        view
        returns (bool found, string memory name)
    {
        for (uint256 i = 0; vm.keyExistsJson(ledger, string.concat("$[", vm.toString(i), "]")); i++) {
            string memory row = string.concat("$[", vm.toString(i), "]");
            if (vm.keyExistsJson(ledger, string.concat(row, ".deprecated"))) continue;
            if (!vm.keyExistsJson(ledger, string.concat(row, ".name"))) continue;
            string memory rowSymbol = vm.parseJsonString(ledger, string.concat(row, ".symbol"));
            if (keccak256(bytes(LibLaunchPlan.toLower(rowSymbol))) == keccak256(bytes(LibLaunchPlan.toLower(symbol)))) {
                found = true;
                name = vm.parseJsonString(ledger, string.concat(row, ".name"));
            }
        }
    }

    function testCommittedLedgerRetiresTheDiscardedEuropeanTokens() external view {
        string[] memory shipped = LibLaunchInputs.readShippedSymbols("launch/launches.json");
        string[6] memory retired = ["tair.pa", "tbmw.de", "tmc.pa", "tsie.de", "tmbg.de", "trhm.de"];
        for (uint256 i = 0; i < retired.length; i++) {
            assertTrue(LibLaunchPlan.contains(shipped, retired[i]), retired[i]);
        }
    }

    function testLedgerRetiredDeprecationStaysShipped() external {
        string memory path = "out/test-launch-ledger-retired.json";
        vm.writeFile(path, '[{"symbol":"tMC.PA","deprecated":{"reason":"discarded","retired":true}}]');
        assertTrue(LibLaunchPlan.contains(LibLaunchInputs.readShippedSymbols(path), "tmc.pa"));
    }

    function testLedgerNonBooleanRetiredFailsClosed() external {
        string memory path = "out/test-launch-ledger-retired-odd.json";
        vm.writeFile(
            path,
            '[{"symbol":"tA","deprecated":{"retired":"true"}},{"symbol":"tB","deprecated":{"retired":1}},'
            '{"symbol":"tC","deprecated":{"retired":"false"}},{"symbol":"tD","deprecated":{"retired":"0"}},'
            '{"symbol":"tE","deprecated":{"retired":2}},{"symbol":"tF","deprecated":{"retired":-1}},'
            '{"symbol":"tG","deprecated":{"retired":"0x1111111111111111111111111111111111111111"}},'
            '{"symbol":"tH","deprecated":{"retired":"yes"}},{"symbol":"tI","deprecated":{"retired":{"a":1}}},'
            '{"symbol":"tJ","deprecated":{"retired":{}}},{"symbol":"tK","deprecated":{"retired":[]}},'
            '{"symbol":"tL","deprecated":{"retired":""}},'
            '{"symbol":"tX","deprecated":{"retired":false}},{"symbol":"tY","deprecated":{"retired":0}},'
            '{"symbol":"tZ","deprecated":{"retired":null}}]'
        );
        string[] memory shipped = LibLaunchInputs.readShippedSymbols(path);
        string[12] memory retired = ["ta", "tb", "tc", "td", "te", "tf", "tg", "th", "ti", "tj", "tk", "tl"];
        assertEq(shipped.length, retired.length);
        for (uint256 i = 0; i < retired.length; i++) {
            assertEq(shipped[i], retired[i]);
        }
    }

    function testLedgerBadDeployStaysPlannable() external {
        string memory path = "out/test-launch-ledger-bad-deploy.json";
        vm.writeFile(path, '[{"symbol":"tQQQM","deprecated":{"reason":"wrong name"}}]');
        assertFalse(LibLaunchPlan.contains(LibLaunchInputs.readShippedSymbols(path), "tqqqm"));
    }

    function testLedgerLiveEntryIsShipped() external {
        string memory path = "out/test-launch-ledger-live.json";
        vm.writeFile(path, '[{"symbol":"tSNES"}]');
        assertTrue(LibLaunchPlan.contains(LibLaunchInputs.readShippedSymbols(path), "tsnes"));
    }

    /// @notice The committed pin file pins tMC to its exclusive minter, never
    /// the shared authoriser.
    function testCommittedPinFilePinsTMcToItsExclusiveMinter() external view {
        DedicatedPin[] memory pins = LibLaunchInputs.readPins("launch/dedicated-authorisers.json");
        (bool found, DedicatedPin memory pin) = LibLaunchPlan.findPin(pins, "tMC");
        assertTrue(found);
        assertEq(pin.chainId, 8453);
        (, address minter) = LibLaunchPlan.parseSetAddress(pin.minter);
        assertEq(minter, MINTER);
        (, address authoriser) = LibLaunchPlan.parseSetAddress(pin.authoriser);
        assertEq(authoriser, LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE);
        assertEq(minter, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        assertEq(pin.deployBlock, 52312053);
        assertTrue(pin.minterGrantPending);
    }

    function testPinLoaderReadsBadDeployBlocksAsUnset() external {
        string memory path = "out/test-launch-pins.json";
        vm.writeFile(
            path,
            '{"tA":{"chainId":8453,"deployBlock":-1},"tB":{"chainId":8453,"deployBlock":1.5},'
            '"tC":{"chainId":8453},"tD":{"chainId":8453,"deployBlock":7,"minterGrantPending":"yes"}}'
        );
        DedicatedPin[] memory pins = LibLaunchInputs.readPins(path);
        assertEq(pins.length, 4);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(pins[i].deployBlock, 0, pins[i].symbol);
        }
        assertEq(pins[3].deployBlock, 7);
        assertFalse(pins[3].minterGrantPending);
    }

    function testPinLoaderReadsOnlyJsonNumbers() external {
        string memory path = "out/test-launch-pins-strings.json";
        vm.writeFile(
            path,
            '{"tA":{"chainId":"8453","deployBlock":"123"},"tB":{"chainId":"0x2105","deployBlock":"0x10"},'
            '"tC":{"chainId":"0x1111111111111111111111111111111111111111","deployBlock":true}}'
        );
        DedicatedPin[] memory pins = LibLaunchInputs.readPins(path);
        assertEq(pins.length, 3);
        for (uint256 i = 0; i < pins.length; i++) {
            assertEq(pins[i].chainId, 0, pins[i].symbol);
            assertEq(pins[i].deployBlock, 0, pins[i].symbol);
        }
    }

    function testPinLoaderReadsOnlyJsonTrueAsGrantPending() external {
        string memory path = "out/test-launch-pins-pending.json";
        vm.writeFile(
            path,
            '{"tA":{"minterGrantPending":false},"tB":{"minterGrantPending":0},"tC":{"minterGrantPending":"true"},'
            '"tD":{"minterGrantPending":null},"tE":{"minterGrantPending":1},"tF":{"minterGrantPending":{"a":1}},'
            '"tG":{"minterGrantPending":true}}'
        );
        DedicatedPin[] memory pins = LibLaunchInputs.readPins(path);
        assertEq(pins.length, 7);
        for (uint256 i = 0; i < 6; i++) {
            assertFalse(pins[i].minterGrantPending, pins[i].symbol);
        }
        assertTrue(pins[6].minterGrantPending);
    }

    function testAllowlistLoaderScopesAuthorisersToBase() external view {
        PlanContext memory ctx = _committedContext();
        assertEq(ctx.allowlistedOwners.length, 1);
        assertEq(ctx.allowlistedOwners[0], LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        assertEq(ctx.allowlistedAuthorisers.length, 2);
        assertEq(ctx.allowlistedAuthorisers[0], LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE);
        assertEq(ctx.allowlistedAuthorisers[1], LibAuthoriserInvariants.STOX_EU_AUTHORISER_CLONE);
    }

    function testIsMetadataFile() external pure {
        assertTrue(LibLaunchInputs.isMetadataFile("launch/metadata/hood.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("metadata/air.pa.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/published/ibhg.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/published/README.md"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/premetadata/hood.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/launches.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a.jsox"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a.joon"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a.json "));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a.xson"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a.jsonx"));
        assertFalse(LibLaunchInputs.isMetadataFile("json"));
        assertFalse(LibLaunchInputs.isMetadataFile(""));
        assertFalse(LibLaunchInputs.isMetadataFile("a.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("etadata/a.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/hoodxjson"));
        assertFalse(LibLaunchInputs.isMetadataFile("test/fixtures/hood.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadatX/hood.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/Metadata/hood.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("a/b/metadata/x.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("../metadata/x.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("Xaunch/metadata/a.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadataX/a.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/"));
        assertFalse(LibLaunchInputs.isMetadataFile("out/metadata/x.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("out/launch/metadata/x.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("out/test-launch-duplicates/metadata/0.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a;b.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/$(x).json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/a b.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/.json"));
        assertFalse(LibLaunchInputs.isMetadataFile("launch/metadata/../x.json"));
        assertTrue(LibLaunchInputs.isMetadataFile("launch/metadata/air.pa.json"));
        assertTrue(LibLaunchInputs.isMetadataFile("launch/metadata/brk-b.json"));
    }

    /// @notice `plan()` reads its inputs from the environment, which every
    /// test in this process shares, so all runs live in this one test.
    function testPlanWritesThePlanFileOrRevertsWithEveryFailure() external {
        vm.writeFile("out/test-launch-ledger-skip.json", '[{"symbol":"tWMT"}]');
        vm.setEnv("LAUNCH_LEDGER", "out/test-launch-ledger-skip.json");
        vm.setEnv("LAUNCH_FILES", "launch/metadata/wmt.json launch/metadata/iau.json");
        vm.setEnv("LAUNCH_PLAN_OUT", "out/test-launch-plan-skip.json");
        uint256 beforeSeconds = vm.unixTime() / 1000;
        script.plan();
        string memory skipJson = vm.readFile("out/test-launch-plan-skip.json");
        uint256 plannedAt = vm.parseJsonUint(skipJson, ".plannedAt");
        assertGe(plannedAt, beforeSeconds);
        assertLe(plannedAt, vm.unixTime() / 1000 + 1);
        assertFalse(vm.keyExistsJson(skipJson, ".tokens.tWMT"));
        string[] memory skipKeys = vm.parseJsonKeys(skipJson, ".tokens");
        assertEq(skipKeys.length, 1);
        assertEq(skipKeys[0], "tIAU");
        assertEq(vm.parseJsonString(skipJson, ".tokens.tIAU.symbol"), "tIAU");
        assertEq(vm.parseJsonString(skipJson, ".ledger"), "out/test-launch-ledger-skip.json");
        assertEq(vm.parseJsonString(skipJson, ".allowlist"), "launch/allowlist.json");
        assertEq(vm.parseJsonString(skipJson, ".pins"), "launch/dedicated-authorisers.json");
        vm.writeFile("out/test-launch-ledger-empty.json", "[]");
        vm.setEnv("LAUNCH_LEDGER", "out/test-launch-ledger-empty.json");
        vm.setEnv(
            "LAUNCH_FILES",
            "launch/metadata/wmt.json launch/metadata/mc.json launch/metadata/iau.json launch/metadata/published/ibhg.json"
        );
        vm.setEnv("LAUNCH_NOW", vm.toString(NOW));
        vm.setEnv("LAUNCH_PLAN_OUT", "out/test-launch-plan.json");
        script.plan();

        string memory planJson = vm.readFile("out/test-launch-plan.json");
        assertEq(vm.parseJsonUint(planJson, ".plannedAt"), NOW);
        assertEq(vm.parseJsonString(planJson, ".tokens.tWMT.name"), "Walmart Inc. ST0x");
        assertEq(vm.parseJsonUint(planJson, ".tokens.tWMT.certifyUntil"), 1818633600);
        assertEq(LibUtcDate.toIsoDate(1818633600), "2027-08-19");
        assertEq(vm.parseJsonAddress(planJson, ".tokens.tWMT.landingAuthoriser"), SHARED);
        assertTrue(vm.parseJsonBool(planJson, ".tokens.tMC.dedicated"));
        assertEq(vm.parseJsonAddress(planJson, ".tokens.tMC.dedicatedMinter"), MINTER);
        assertFalse(vm.keyExistsJson(planJson, ".tokens.tIBHG"));
        string[] memory tokenKeys = vm.parseJsonKeys(planJson, ".tokens");
        assertEq(tokenKeys.length, 3);
        assertEq(vm.parseJsonString(planJson, ".tokens.tWMT.symbol"), "tWMT");
        assertEq(vm.parseJsonString(planJson, ".tokens.tWMT.metadataFile"), "launch/metadata/wmt.json");
        assertEq(vm.parseJsonString(planJson, ".tokens.tWMT.type"), "equity");
        assertEq(vm.parseJsonString(planJson, ".tokens.tIAU.type"), "etf");
        assertEq(
            vm.parseJsonAddress(planJson, ".tokens.tWMT.intendedOwner"), 0xe70d821f3462a074e63b42d0AaC6523faAe1d611
        );
        assertFalse(vm.parseJsonBool(planJson, ".tokens.tWMT.dedicated"));
        assertEq(vm.parseJsonAddress(planJson, ".tokens.tWMT.dedicatedMinter"), address(0));
        assertEq(vm.parseJsonUint(planJson, ".tokens.tWMT.dedicatedDeployBlock"), 0);
        assertEq(vm.parseJsonUint(planJson, ".tokens.tMC.dedicatedDeployBlock"), 52312053);
        assertTrue(vm.parseJsonBool(planJson, ".tokens.tMC.dedicatedMinterGrantPending"));
        assertFalse(vm.parseJsonBool(planJson, ".tokens.tWMT.dedicatedMinterGrantPending"));

        vm.setEnv("LAUNCH_FILES", "launch/metadata/spy.json");
        vm.setEnv("LAUNCH_PLAN_OUT", "out/test-launch-plan-second.json");
        script.plan();
        string[] memory secondKeys = vm.parseJsonKeys(vm.readFile("out/test-launch-plan-second.json"), ".tokens");
        assertEq(secondKeys.length, 1);
        assertEq(secondKeys[0], "tSPY");

        address planner = vm.computeCreateAddress(address(script), vm.getNonce(address(script)));
        vm.mockCallRevert(planner, abi.encodeWithSelector(LaunchFilePlanner.planFile.selector), "");
        vm.etch(planner, "");
        vm.setEnv("LAUNCH_FILES", "launch/metadata/wmt.json");
        vm.setEnv("LAUNCH_PLAN_OUT", "out/test-launch-plan-empty-revert.json");
        if (vm.exists("out/test-launch-plan-empty-revert.json")) {
            vm.removeFile("out/test-launch-plan-empty-revert.json");
        }
        vm.expectRevert(abi.encodeWithSelector(LaunchPlanInvalid.selector, 1));
        script.plan();
        assertFalse(vm.exists("out/test-launch-plan-empty-revert.json"));
        vm.clearMockedCalls();

        vm.writeFile("out/test-launch-allowlist-no-owner.json", "[]");
        vm.setEnv("LAUNCH_ALLOWLIST", "out/test-launch-allowlist-no-owner.json");
        vm.setEnv("LAUNCH_FILES", "launch/metadata/wmt.json launch/metadata/iau.json");
        vm.expectRevert(abi.encodeWithSelector(LaunchPlanInvalid.selector, 2));
        script.plan();

        vm.setEnv("LAUNCH_ALLOWLIST", "launch/allowlist.json");
        vm.setEnv("LAUNCH_LEDGER", "test/fixtures/launch/launches-ee39d0d.json");
        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchInputOutsideOut.selector, "LAUNCH_LEDGER", "test/fixtures/launch/launches-ee39d0d.json"
            )
        );
        script.plan();
        vm.setEnv("LAUNCH_LEDGER", "out/test-launch-ledger-empty.json");
        vm.setEnv("LAUNCH_PLAN_OUT", "launch/launches.json");
        vm.expectRevert(
            abi.encodeWithSelector(LaunchInputOutsideOut.selector, "LAUNCH_PLAN_OUT", "launch/launches.json")
        );
        script.plan();
        vm.setEnv("LAUNCH_PLAN_OUT", "out/../launch/launches.json");
        vm.expectRevert(
            abi.encodeWithSelector(LaunchInputOutsideOut.selector, "LAUNCH_PLAN_OUT", "out/../launch/launches.json")
        );
        script.plan();
    }

    function testDescribeOutcomesListsEveryLine() external view {
        LaunchBaseTokens.FileOutcome[] memory outcomes = new LaunchBaseTokens.FileOutcome[](4);
        outcomes[0].metadataFile = "launch/metadata/wmt.json";
        outcomes[0].skipped = true;
        outcomes[1].metadataFile = "launch/metadata/iau.json";
        outcomes[1].plan.symbol = "tIAU";
        outcomes[1].plan.name = "iShares Gold Trust ST0x";
        outcomes[1].plan.assetType = AssetType.Etf;
        outcomes[1].plan.certifyUntil = 1818633600;
        outcomes[2].metadataFile = "launch/metadata/mc.json";
        outcomes[2].plan.symbol = "tMC";
        outcomes[2].plan.name = "LVMH ST0x";
        outcomes[2].plan.certifyUntil = 1818633600;
        outcomes[2].plan.dedicated = true;
        outcomes[2].plan.landingAuthoriser = address(1);
        outcomes[2].plan.dedicatedMinter = address(2);
        outcomes[2].plan.dedicatedMinterGrantPending = true;
        outcomes[3].metadataFile = "launch/metadata/a.json";
        outcomes[3].failed = true;
        outcomes[3].failure = abi.encodeWithSelector(MissingName.selector);
        (string[] memory lines, uint256 failures) = script.describeOutcomes(outcomes);
        assertEq(failures, 1);
        assertEq(lines.length, 5);
        assertEq(lines[0], "  skip  launch/metadata/wmt.json (already in the ledger)");
        assertEq(lines[1], "  plan  tIAU \"iShares Gold Trust ST0x\" type=etf certify-until=2027-08-19");
        assertEq(lines[2], "  plan  tMC \"LVMH ST0x\" type=equity certify-until=2027-08-19");
        assertEq(
            lines[3],
            "        authorizer=0x0000000000000000000000000000000000000001 (dedicated, minter 0x0000000000000000000000000000000000000002, grant pending)"
        );
        assertEq(lines[4], "  FAIL  launch/metadata/a.json - name is missing");

        LaunchBaseTokens.FileOutcome[] memory skippedOnly = new LaunchBaseTokens.FileOutcome[](1);
        skippedOnly[0] = outcomes[0];
        (lines, failures) = script.describeOutcomes(skippedOnly);
        assertEq(failures, 0);
        assertEq(lines.length, 2);
        assertEq(lines[1], "  nothing to deploy");

        LaunchBaseTokens.FileOutcome[] memory failedOnly = new LaunchBaseTokens.FileOutcome[](1);
        failedOnly[0] = outcomes[3];
        failedOnly[0].failure = "";
        (lines, failures) = script.describeOutcomes(failedOnly);
        assertEq(failures, 1);
        assertEq(lines.length, 1);
        assertEq(lines[0], "  FAIL  launch/metadata/a.json - unreadable");
    }

    function testDescribePlanMatchesThePlan() external view {
        TokenPlan memory tokenPlan;
        tokenPlan.symbol = "tIAU";
        tokenPlan.name = "iShares Gold Trust ST0x";
        tokenPlan.assetType = AssetType.Etf;
        tokenPlan.certifyUntil = 1818633600;
        (string memory line, string memory dedicatedLine) = script.describePlan(tokenPlan);
        assertEq(line, "  plan  tIAU \"iShares Gold Trust ST0x\" type=etf certify-until=2027-08-19");
        assertEq(dedicatedLine, "");
        tokenPlan.assetType = AssetType.Equity;
        tokenPlan.dedicated = true;
        tokenPlan.landingAuthoriser = address(1);
        tokenPlan.dedicatedMinter = address(2);
        tokenPlan.dedicatedMinterGrantPending = true;
        (line, dedicatedLine) = script.describePlan(tokenPlan);
        assertEq(line, "  plan  tIAU \"iShares Gold Trust ST0x\" type=equity certify-until=2027-08-19");
        assertEq(
            dedicatedLine,
            "        authorizer=0x0000000000000000000000000000000000000001 (dedicated, minter 0x0000000000000000000000000000000000000002, grant pending)"
        );
        tokenPlan.dedicatedMinterGrantPending = false;
        (, dedicatedLine) = script.describePlan(tokenPlan);
        assertEq(
            dedicatedLine,
            "        authorizer=0x0000000000000000000000000000000000000001 (dedicated, minter 0x0000000000000000000000000000000000000002)"
        );
    }

    /// @notice A later duplicate names the first planned file, not an earlier
    /// duplicate that was itself refused.
    function testDuplicateNamesTheFirstPlannedFile() external {
        address planner = vm.computeCreateAddress(address(script), vm.getNonce(address(script)));
        TokenPlan memory tokenPlan;
        tokenPlan.symbol = "tWMT";
        vm.mockCall(planner, abi.encodeWithSelector(LaunchFilePlanner.planFile.selector), abi.encode(false, tokenPlan));
        vm.etch(planner, "");
        string[] memory files = new string[](3);
        files[0] = "launch/metadata/a.json";
        files[1] = "launch/metadata/b.json";
        files[2] = "launch/metadata/c.json";
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(files, _committedContext());
        assertFalse(outcomes[0].failed);
        assertEq(outcomes[1].failure, abi.encodeWithSelector(DuplicateSymbol.selector, "tWMT", files[0]));
        assertEq(outcomes[2].failure, abi.encodeWithSelector(DuplicateSymbol.selector, "tWMT", files[0]));
    }

    function testDescribeFailureNamesTheField() external view {
        assertEq(script.describeFailure(""), "unreadable");
        assertEq(script.describeFailure(abi.encodeWithSignature("Error(string)", "file not found")), "file not found");
        assertEq(
            script.describeFailureLine("launch/metadata/a.json", abi.encodeWithSelector(MissingName.selector)),
            "  FAIL  launch/metadata/a.json - name is missing"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(UnsupportedAssetType.selector, "Fund")),
            "asset_type must be \"Equity\" or \"ETF\", got \"Fund\""
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(InvalidCounterparties.selector)),
            "offchain_counterparties must be exactly the US set [AlpacaDB Inc, Clear Street LLC] or the non-US set"
            " [AlpacaDB Inc, Clear Street LLC, Freedom Finance] - pre-2026-08-19 files carry the retired set"
        );
    }

    function testLedgerNullAndFalseDeprecationStayShipped() external {
        string memory path = "out/test-launch-ledger-null.json";
        vm.writeFile(path, '[{"symbol":"tA","deprecated":null},{"symbol":"tB","deprecated":false}]');
        string[] memory shipped = LibLaunchInputs.readShippedSymbols(path);
        assertEq(shipped.length, 2);
        assertEq(shipped[0], "ta");
        assertEq(shipped[1], "tb");
    }

    function testAllowlistLoaderFiltersByChainAndRole() external {
        string memory path = "out/test-launch-allowlist.json";
        vm.writeFile(
            path,
            '[{"address":"0x1111111111111111111111111111111111111111","chainId":1,"roles":["authorizer"]},'
            '{"address":"0x2222222222222222222222222222222222222222","chainId":8453,"roles":["authorizer"]},'
            '{"address":"0x3333333333333333333333333333333333333333","chainId":1,"roles":["owner"]},'
            '{"address":"0x4444444444444444444444444444444444444444","chainId":8453,"roles":["minter"]}]'
        );
        PlanContext memory ctx =
            script.planContext("launch/launches.json", path, "launch/dedicated-authorisers.json", NOW);
        assertEq(ctx.allowlistedAuthorisers.length, 1);
        assertEq(ctx.allowlistedAuthorisers[0], 0x2222222222222222222222222222222222222222);
        assertEq(ctx.allowlistedOwners.length, 1);
        assertEq(ctx.allowlistedOwners[0], 0x3333333333333333333333333333333333333333);

        vm.writeFile(
            path, '[{"address":"0x2222222222222222222222222222222222222222","chainId":"8453","roles":["authorizer"]}]'
        );
        assertEq(LibLaunchInputs.readAllowlisted(path, "authorizer", 8453).length, 0);
    }

    function testReadMetadataReadsEveryField() external view {
        LaunchMetadata memory metadata = LibLaunchInputs.readMetadata("launch/metadata/mc.json");
        assertEq(metadata.primaryTicker, "MC");
        assertEq(metadata.assetType, "Equity");
        assertEq(metadata.name, unicode"LVMH Moët Hennessy Louis Vuitton SE");
        assertEq(metadata.countryIso, "FR");
        assertEq(metadata.isin, "FR0000121014");
        assertEq(metadata.counterparties.length, 3);
        assertEq(metadata.counterparties[0], "AlpacaDB Inc");
        assertEq(metadata.counterparties[1], "Clear Street LLC");
        assertEq(metadata.counterparties[2], "Freedom Finance");
    }

    function testReadMetadataDefaultsMissingFieldsToEmpty() external {
        string memory path = "out/test-launch-metadata-empty.json";
        vm.writeFile(path, "{}");
        LaunchMetadata memory metadata = LibLaunchInputs.readMetadata(path);
        assertEq(metadata.primaryTicker, "");
        assertEq(metadata.assetType, "");
        assertEq(metadata.name, "");
        assertEq(metadata.countryIso, "");
        assertEq(metadata.isin, "");
        assertEq(metadata.counterparties.length, 0);
        vm.writeFile(path, '{"offchain_counterparties":[{}]}');
        metadata = LibLaunchInputs.readMetadata(path);
        assertEq(metadata.counterparties.length, 1);
        assertEq(metadata.counterparties[0], "");
    }

    function testAnEmptyPlannerRevertIsAFailure() external {
        address planner = vm.computeCreateAddress(address(script), vm.getNonce(address(script)));
        vm.mockCallRevert(planner, abi.encodeWithSelector(LaunchFilePlanner.planFile.selector), "");
        vm.etch(planner, "");
        string[] memory files = new string[](1);
        files[0] = "launch/metadata/wmt.json";
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(files, _committedContext());
        assertEq(outcomes.length, 1);
        assertTrue(outcomes[0].failed);
        assertEq(outcomes[0].failure.length, 0);
        assertFalse(outcomes[0].skipped);
        assertEq(script.describeFailure(outcomes[0].failure), "unreadable");
    }

    function testDescribeFailureHandlesEveryRefusalAndUnknownBytes() external view {
        assertEq(script.describeFailure(""), "unreadable");
        assertEq(script.describeFailure(hex"01"), "unreadable");
        assertEq(script.describeFailure(hex"0102"), "unreadable");
        assertEq(script.describeFailure(hex"010203"), "unreadable");
        assertEq(script.describeFailure(hex"01020304"), "0x01020304");
        assertEq(
            script.describeFailure(abi.encodeWithSelector(MissingPrimaryTicker.selector)), "primary_ticker is missing"
        );
        assertEq(script.describeFailure(abi.encodeWithSelector(MissingName.selector)), "name is missing");
        assertEq(
            script.describeFailure(abi.encodeWithSelector(InvalidTicker.selector, "A;B")),
            "primary_ticker may hold only ASCII letters, digits, '.' and '-', got \"A;B\""
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(DuplicateSymbol.selector, "tWMT", "a.json")),
            "tWMT is also planned from a.json"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(NameIsTicker.selector, "HOOD")),
            "name is the ticker (HOOD), not the asset name"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(ControlCharacterInName.selector, "A\nB")),
            "name holds a control character: 0x410a42"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(UnicodeWhitespaceInName.selector, "Foo")),
            "name holds Unicode whitespace: \"Foo\""
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(InvalidCountryIso.selector, "USA")),
            "country.iso must be a 2-letter code, got \"USA\""
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(InvalidIsin.selector, "bad")),
            "isin is missing or malformed: \"bad\""
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(OwnerNotAllowlisted.selector, address(1))),
            "0x0000000000000000000000000000000000000001 is not an allowlisted owner"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(DedicatedPinWrongChain.selector, "tMC", 1)),
            "tMC: dedicated authoriser pin is for chainId 1, not Base"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(DedicatedAuthoriserUnset.selector, "tMC", "bad")),
            "tMC requires a dedicated authoriser but none is pinned (got \"bad\")"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(DedicatedAuthoriserIsShared.selector, "tMC")),
            "tMC: dedicated authoriser is the shared authoriser"
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(DedicatedMinterUnset.selector, "tMC", "bad")),
            "tMC: dedicated minter is unset or malformed: \"bad\""
        );
        assertEq(
            script.describeFailure(abi.encodeWithSelector(DedicatedDeployBlockUnset.selector, "tMC")),
            "tMC: dedicated authoriser deployBlock is unset"
        );
        assertEq(
            script.describeFailure(
                abi.encodeWithSelector(DedicatedAuthoriserNotAllowlisted.selector, "tMC", address(1))
            ),
            "tMC: dedicated authoriser 0x0000000000000000000000000000000000000001 is not allowlisted as authorizer on Base"
        );
    }

    function testPinLoaderPreservesWrongChainForThePlanRefusal() external {
        string memory pinsPath = "out/test-launch-pins-chain.json";
        vm.writeFile(
            pinsPath,
            '{"tMC":{"chainId":1,"authorizer":"0xDB9152e46c1D140DB6a6f814461f21c571F3275e",'
            '"minter":"0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C","deployBlock":5}}'
        );
        DedicatedPin[] memory pins = LibLaunchInputs.readPins(pinsPath);
        assertEq(pins.length, 1);
        assertEq(pins[0].chainId, 1);
        vm.writeFile("out/test-launch-ledger-chain.json", "[]");
        string[] memory files = new string[](1);
        files[0] = "launch/metadata/mc.json";
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(
            files, script.planContext("out/test-launch-ledger-chain.json", "launch/allowlist.json", pinsPath, NOW)
        );
        assertEq(outcomes.length, 1);
        assertEq(outcomes[0].failure, abi.encodeWithSelector(DedicatedPinWrongChain.selector, "tMC", 1));
    }

    function testLoaderFieldShapesKeepTheExistingSkipAndFallbackRules() external {
        string memory ledgerPath = "out/test-launch-ledger-shapes.json";
        vm.writeFile(
            ledgerPath,
            '[{"symbol":"tA","deprecated":{}},{"symbol":"tB","deprecated":[]},'
            '{"symbol":"tC","deprecated":true},{"symbol":"tD","deprecated":"x"},{"symbol":"tE","deprecated":{"a":0}},'
            '{"symbol":"tF","deprecated":{"retired":false}},{"symbol":"tG","deprecated":1},'
            '{"symbol":"tH","deprecated":""},{"symbol":"tI","deprecated":0},{"name":"no symbol"},{"symbol":""}]'
        );
        string[] memory shipped = LibLaunchInputs.readShippedSymbols(ledgerPath);
        assertEq(shipped.length, 2);
        assertEq(shipped[0], "th");
        assertEq(shipped[1], "ti");
        string memory metadataPath = "out/test-launch-metadata-shapes.json";
        vm.writeFile(
            metadataPath,
            '{"primary_ticker":["HOOD"],"isin":{"v":"US7707001027"},"name":null,"asset_type":true,"country":{"iso":12}}'
        );
        LaunchMetadata memory metadata = LibLaunchInputs.readMetadata(metadataPath);
        assertEq(metadata.primaryTicker, "");
        assertEq(metadata.isin, "");
        assertEq(metadata.name, "");
        assertEq(metadata.assetType, "true");
        assertEq(metadata.countryIso, "12");
        vm.writeFile(metadataPath, '{"name":"null"}');
        assertEq(LibLaunchInputs.readMetadata(metadataPath).name, "null");
        string memory allowlistPath = "out/test-launch-allowlist-shapes.json";
        vm.writeFile(
            allowlistPath, '[{"address":"0x1111111111111111111111111111111111111111","chainId":8453,"roles":"owner"}]'
        );
        assertEq(LibLaunchInputs.readAllowlisted(allowlistPath, "owner", 0).length, 0);
    }
}
