// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LaunchBaseTokens, LaunchPlanInvalid, DuplicateSymbol} from "../../script/20261020-launch-base-tokens.s.sol";
import {LaunchFilePlanner} from "../../script/lib/LaunchFilePlanner.sol";
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
        Vm.DirEntry[] memory entries = vm.readDir("launch/metadata", 2);
        files = new string[](entries.length);
        for (uint256 i = 0; i < entries.length; i++) {
            files[i] = string.concat("launch/metadata/", _relative(entries[i].path));
        }
    }

    /// @dev `readDir` paths are absolute; keep what follows `launch/metadata/`.
    function _relative(string memory path) internal pure returns (string memory) {
        bytes memory b = bytes(path);
        bytes memory marker = "launch/metadata/";
        for (uint256 i = 0; i + marker.length <= b.length; i++) {
            bool hit = true;
            for (uint256 j = 0; j < marker.length; j++) {
                if (b[i + j] != marker[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) {
                bytes memory rest = new bytes(b.length - i - marker.length);
                for (uint256 k = 0; k < rest.length; k++) {
                    rest[k] = b[i + marker.length + k];
                }
                return string(rest);
            }
        }
        return path;
    }

    /// @notice Every committed metadata file plans cleanly: a symbol already
    /// live or retired in the committed ledger skips, any other plans with no
    /// refusal, on the shared authoriser unless it is pinned. `published/` and
    /// its README are never inputs.
    function testCommittedMetadataPlansAsSftOpsDoes() external {
        PlanContext memory ctx = _committedContext();
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(_metadataFiles(), ctx);
        uint256 inputs = 0;
        string[] memory files = _metadataFiles();
        for (uint256 i = 0; i < files.length; i++) {
            if (LibLaunchInputs.isMetadataFile(files[i])) inputs++;
        }
        assertEq(outcomes.length, inputs);
        for (uint256 i = 0; i < outcomes.length; i++) {
            assertEq(outcomes[i].failure.length, 0, outcomes[i].metadataFile);
            string memory json = vm.readFile(outcomes[i].metadataFile);
            string memory symbol = string.concat(
                "t", LibLaunchPlan.toUpper(LibLaunchPlan.trim(vm.parseJsonString(json, ".primary_ticker")))
            );
            bool shipped = LibLaunchPlan.contains(ctx.shippedSymbols, LibLaunchPlan.toLower(symbol));
            assertEq(outcomes[i].skipped, shipped, outcomes[i].metadataFile);
            if (shipped) continue;
            assertEq(outcomes[i].plan.symbol, symbol);
            (bool pinned,) = LibLaunchPlan.findPin(ctx.pins, symbol);
            if (!pinned) assertEq(outcomes[i].plan.landingAuthoriser, SHARED);
        }
    }

    /// @notice sft-ops `cd-plan` on the files copied from sft-ops `ee39d0d`
    /// planned exactly tFGI and skipped the rest.
    function testCopiedSnapshotPlansOnlyFgi() external {
        string[] memory files = vm.parseJsonStringArray(vm.readFile("test/fixtures/launch/metadata-ee39d0d.json"), "$");
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(
            files,
            script.planContext(
                "test/fixtures/launch/launches-ee39d0d.json",
                "launch/allowlist.json",
                "launch/dedicated-authorisers.json",
                NOW
            )
        );
        assertEq(outcomes.length, 63);
        uint256 planned;
        for (uint256 i = 0; i < outcomes.length; i++) {
            assertEq(outcomes[i].failure.length, 0, outcomes[i].metadataFile);
            if (outcomes[i].skipped) continue;
            planned++;
            assertEq(outcomes[i].metadataFile, "launch/metadata/fgi.json");
            assertEq(outcomes[i].plan.symbol, "tFGI");
            assertEq(outcomes[i].plan.name, "FGI Industries Ltd. ST0x");
        }
        assertEq(planned, 1);
    }

    function testABatchCannotPlanOneSymbolTwice() external {
        vm.writeFile("out/test-launch-ledger-dup.json", "[]");
        string[] memory files = new string[](3);
        vm.createDir("out/test-launch-duplicates/metadata", true);
        for (uint256 i = 0; i < files.length; i++) {
            files[i] = string.concat("out/test-launch-duplicates/metadata/", vm.toString(i), ".json");
            vm.writeFile(files[i], vm.readFile("launch/metadata/wmt.json"));
        }
        LaunchBaseTokens.FileOutcome[] memory outcomes = script.planFiles(
            files,
            script.planContext(
                "out/test-launch-ledger-dup.json", "launch/allowlist.json", "launch/dedicated-authorisers.json", NOW
            )
        );
        assertEq(outcomes[0].failure.length, 0);
        for (uint256 i = 1; i < outcomes.length; i++) {
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
            '[{"symbol":"tX","deprecated":{"retired":"true"}},{"symbol":"tY","deprecated":{"retired":1}},'
            '{"symbol":"tZ","deprecated":{"retired":false}},{"symbol":"tW","deprecated":{"retired":"false"}},'
            '{"symbol":"tV","deprecated":{"retired":"0"}},{"symbol":"tU","deprecated":{"retired":0}}]'
        );
        string[] memory shipped = LibLaunchInputs.readShippedSymbols(path);
        // JSON `0` encodes as the same word as `false`, so tU stays plannable.
        assertEq(shipped.length, 4);
        assertEq(shipped[0], "tx");
        assertEq(shipped[1], "ty");
        assertEq(shipped[2], "tw");
        assertEq(shipped[3], "tv");
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
        assertTrue(LibLaunchInputs.isMetadataFile("out/test-launch-duplicates/metadata/0.json"));
    }

    /// @notice `plan()` reads its inputs from the environment, which every
    /// test in this process shares, so all runs live in this one test.
    function testPlanWritesThePlanFileOrRevertsWithEveryFailure() external {
        vm.writeFile("out/test-launch-ledger-skip.json", '[{"symbol":"tWMT"}]');
        vm.setEnv("LAUNCH_LEDGER", "out/test-launch-ledger-skip.json");
        vm.setEnv("LAUNCH_FILES", "launch/metadata/wmt.json launch/metadata/iau.json");
        vm.setEnv("LAUNCH_PLAN", "out/test-launch-plan-skip.json");
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
        vm.writeFile("out/test-launch-ledger-empty.json", "[]");
        vm.setEnv("LAUNCH_LEDGER", "out/test-launch-ledger-empty.json");
        vm.setEnv(
            "LAUNCH_FILES",
            "launch/metadata/wmt.json launch/metadata/mc.json launch/metadata/iau.json launch/metadata/published/ibhg.json"
        );
        vm.setEnv("LAUNCH_NOW", vm.toString(NOW));
        vm.setEnv("LAUNCH_PLAN", "out/test-launch-plan.json");
        script.plan();

        string memory planJson = vm.readFile("out/test-launch-plan.json");
        assertEq(vm.parseJsonUint(planJson, ".plannedAt"), NOW);
        assertEq(vm.parseJsonString(planJson, ".tokens.tWMT.name"), "Walmart Inc. ST0x");
        assertEq(LibUtcDate.toIsoDate(vm.parseJsonUint(planJson, ".tokens.tWMT.certifyUntil")), "2027-08-19");
        assertEq(vm.parseJsonAddress(planJson, ".tokens.tWMT.landingAuthoriser"), SHARED);
        assertTrue(vm.parseJsonBool(planJson, ".tokens.tMC.dedicated"));
        assertEq(vm.parseJsonAddress(planJson, ".tokens.tMC.dedicatedMinter"), MINTER);
        assertFalse(vm.keyExistsJson(planJson, ".tokens.tIBHG"));
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

        vm.createDir("out/test-launch-bad/metadata", true);
        vm.writeFile("out/test-launch-bad/metadata/a.json", '{"primary_ticker":"AAA","asset_type":"Fund"}');
        vm.writeFile("out/test-launch-bad/metadata/b.json", '{"primary_ticker":"BBB","asset_type":"ETF","name":"B"}');
        vm.setEnv("LAUNCH_FILES", "out/test-launch-bad/metadata/a.json out/test-launch-bad/metadata/b.json");
        vm.expectRevert(abi.encodeWithSelector(LaunchPlanInvalid.selector, 2));
        script.plan();
    }

    function testDescribePlanMatchesThePlan() external view {
        TokenPlan memory p;
        p.symbol = "tIAU";
        p.name = "iShares Gold Trust ST0x";
        p.assetType = AssetType.Etf;
        p.certifyUntil = 1818633600;
        (string memory line, string memory dedicatedLine) = script.describePlan(p);
        assertEq(line, "  plan  tIAU \"iShares Gold Trust ST0x\" type=etf certify-until=2027-08-19");
        assertEq(dedicatedLine, "");
        p.assetType = AssetType.Equity;
        p.dedicated = true;
        p.landingAuthoriser = address(1);
        p.dedicatedMinter = address(2);
        p.dedicatedMinterGrantPending = true;
        (line, dedicatedLine) = script.describePlan(p);
        assertEq(line, "  plan  tIAU \"iShares Gold Trust ST0x\" type=equity certify-until=2027-08-19");
        assertEq(
            dedicatedLine,
            "        authorizer=0x0000000000000000000000000000000000000001 (dedicated, minter 0x0000000000000000000000000000000000000002, grant pending)"
        );
    }

    function testDescribeFailureNamesTheField() external view {
        assertEq(script.describeFailure(""), "unreadable");
        assertEq(script.describeFailure(bytes("unreadable")), "unreadable");
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
        assertEq(outcomes[0].failure, bytes("unreadable"));
        assertEq(script.describeFailure(outcomes[0].failure), "unreadable");
        assertFalse(outcomes[0].skipped);

        address plannerAgain = vm.computeCreateAddress(address(script), vm.getNonce(address(script)));
        vm.mockCallRevert(plannerAgain, abi.encodeWithSelector(LaunchFilePlanner.planFile.selector), "");
        vm.etch(plannerAgain, "");
        vm.setEnv("LAUNCH_FILES", "launch/metadata/wmt.json");
        vm.expectRevert(abi.encodeWithSelector(LaunchPlanInvalid.selector, 1));
        script.plan();
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
            '{"symbol":"tC","deprecated":true},{"symbol":"tD","deprecated":"x"}]'
        );
        string[] memory shipped = LibLaunchInputs.readShippedSymbols(ledgerPath);
        assertEq(shipped.length, 1);
        assertEq(shipped[0], "ta");
        string memory metadataPath = "out/test-launch-metadata-shapes.json";
        vm.writeFile(metadataPath, '{"primary_ticker":["HOOD"],"isin":{"v":"US7707001027"}}');
        LaunchMetadata memory metadata = LibLaunchInputs.readMetadata(metadataPath);
        assertEq(metadata.primaryTicker, "");
        assertEq(metadata.isin, "");
        string memory allowlistPath = "out/test-launch-allowlist-shapes.json";
        vm.writeFile(
            allowlistPath, '[{"address":"0x1111111111111111111111111111111111111111","chainId":8453,"roles":"owner"}]'
        );
        assertEq(LibLaunchInputs.readAllowlisted(allowlistPath, "owner", 0).length, 0);
    }
}
