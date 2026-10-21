// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Bytes} from "@openzeppelin-contracts-5.7.0/utils/Bytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibUtcDate} from "../src/lib/LibUtcDate.sol";
import {
    LibLaunchPlan,
    LaunchMetadata,
    PlanContext,
    TokenPlan,
    AssetType,
    MissingPrimaryTicker,
    InvalidTicker,
    UnsupportedAssetType,
    MissingName,
    NameIsTicker,
    UnicodeWhitespaceInName,
    ControlCharacterInName,
    InvalidCountryIso,
    InvalidIsin,
    InvalidCounterparties,
    OwnerNotAllowlisted,
    DedicatedPinWrongChain,
    DedicatedAuthoriserUnset,
    DedicatedAuthoriserIsShared,
    DedicatedMinterUnset,
    DedicatedDeployBlockUnset,
    DedicatedAuthoriserNotAllowlisted
} from "../src/lib/LibLaunchPlan.sol";
import {LibLaunchInputs} from "./lib/LibLaunchInputs.sol";
import {LaunchFilePlanner} from "./LaunchFilePlanner.sol";

/// @notice At least one metadata file failed its checks. Every failure is
/// logged before this reverts.
/// @param failures How many files failed.
error LaunchPlanInvalid(uint256 failures);

/// @notice Two files in one batch derive the same symbol. Launching both would
/// deploy the token twice.
error DuplicateSymbol(string symbol, string firstFile);

/// @notice An environment override of a launch input names a path outside
/// `out/`, or one holding `..`. Overrides exist for tests and the end-to-end rehearsal, which stage
/// their inputs there.
error LaunchInputOutsideOut(string name, string path);

/// @title LaunchBaseTokens
/// @notice The Base token launch ported from sft-ops: `plan()` is its
/// `cd-plan`. Each `launch/metadata/<ticker>.json` named in `LAUNCH_FILES`
/// (space-separated) is checked and turned into launch arguments, written to
/// the plan file.
///
/// Environment:
/// - `LAUNCH_FILES`: the changed files; paths that are not deploy inputs are
///   ignored. Default none.
/// - `LAUNCH_NOW`: unix seconds the certification year counts from. Default
///   the current time.
/// - `LAUNCH_LEDGER`, `LAUNCH_ALLOWLIST`, `LAUNCH_PINS`: the ledger, allowlist
///   and dedicated-authoriser pins. Default the committed files under
///   `launch/`; an override must be under `out/`.
/// - `LAUNCH_PLAN_OUT`: the plan file. Default `out/launch-plan.json`; an
///   override must be under `out/`.
contract LaunchBaseTokens is Script {
    string internal constant DEFAULT_LEDGER = "launch/launches.json";
    string internal constant DEFAULT_PINS = "launch/dedicated-authorisers.json";
    string internal constant DEFAULT_ALLOWLIST = "launch/allowlist.json";
    string internal constant DEFAULT_PLAN_OUT = "out/launch-plan.json";

    /// @notice One file's outcome, for the log and the plan file. `ignored`
    /// marks a path that is not a deploy input. `failure` holds the revert
    /// data, which may be empty when `failed`.
    struct FileOutcome {
        string metadataFile;
        bool ignored;
        bool skipped;
        bool failed;
        bytes failure;
        TokenPlan plan;
    }

    /// @notice The input files a plan was made from.
    struct PlanInputs {
        string ledger;
        string allowlist;
        string pins;
    }

    /// @notice Plan the files in `LAUNCH_FILES`, log every outcome and write
    /// the plan file. When any file is refused it reverts after logging and
    /// writes no plan file.
    function plan() external {
        string[] memory files = vm.envOr("LAUNCH_FILES", " ", new string[](0));
        uint256 nowSeconds = vm.envOr("LAUNCH_NOW", vm.unixTime() / 1000);
        PlanInputs memory inputs = PlanInputs({
            ledger: _inputPath("LAUNCH_LEDGER", DEFAULT_LEDGER),
            allowlist: _inputPath("LAUNCH_ALLOWLIST", DEFAULT_ALLOWLIST),
            pins: _inputPath("LAUNCH_PINS", DEFAULT_PINS)
        });
        string memory planOut = _inputPath("LAUNCH_PLAN_OUT", DEFAULT_PLAN_OUT);

        FileOutcome[] memory outcomes =
            planFiles(files, planContext(inputs.ledger, inputs.allowlist, inputs.pins, nowSeconds));

        (string[] memory lines, uint256 failures) = describeOutcomes(outcomes);
        for (uint256 i = 0; i < lines.length; i++) {
            console2.log(lines[i]);
        }
        if (failures != 0) revert LaunchPlanInvalid(failures);

        vm.writeJson(_planJson(outcomes, inputs, nowSeconds), planOut);
    }

    /// @notice Everything the plan depends on besides the metadata files.
    /// @param ledger The launch ledger.
    /// @param allowlist The owner and authoriser allowlist.
    /// @param pins The dedicated-authoriser pins.
    /// @param nowSeconds Unix seconds the certification year counts from.
    /// @return ctx The plan context.
    function planContext(string memory ledger, string memory allowlist, string memory pins, uint256 nowSeconds)
        public
        view
        returns (PlanContext memory ctx)
    {
        ctx.shippedSymbols = LibLaunchInputs.readShippedSymbols(ledger);
        ctx.allowlistedOwners = LibLaunchInputs.readAllowlisted(allowlist, "owner", 0);
        ctx.allowlistedAuthorisers =
            LibLaunchInputs.readAllowlisted(allowlist, "authorizer", LibSafeInvariants.BASE_CHAIN_ID);
        ctx.pins = LibLaunchInputs.readPins(pins);
        ctx.ownerSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        ctx.sharedAuthoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        ctx.now = nowSeconds;
    }

    /// @notice Plan every deploy input in `files`; any other non-empty path is
    /// an ignored outcome, so it shows in the log.
    /// @param files The changed files.
    /// @param ctx The plan context.
    /// @return outcomes One outcome per non-empty path, in `files` order.
    function planFiles(string[] memory files, PlanContext memory ctx) public returns (FileOutcome[] memory outcomes) {
        FileOutcome[] memory all = new FileOutcome[](files.length);
        LaunchFilePlanner planner = new LaunchFilePlanner();
        uint256 inputCount = 0;
        for (uint256 i = 0; i < files.length; i++) {
            if (bytes(files[i]).length == 0) continue;
            FileOutcome memory outcome = all[inputCount++];
            outcome.metadataFile = files[i];
            if (!LibLaunchInputs.isMetadataFile(files[i])) {
                outcome.ignored = true;
                continue;
            }
            try planner.planFile(files[i], ctx) returns (bool skipped, TokenPlan memory tokenPlan) {
                outcome.skipped = skipped;
                outcome.plan = tokenPlan;
                // Skipping depends only on the symbol, so a duplicate of a
                // skipped file is skipped too and needs no check.
                for (uint256 j = 0; j + 1 < inputCount && !skipped; j++) {
                    if (
                        !all[j].failed
                            && Strings.equal(
                                LibLaunchPlan.toLower(all[j].plan.symbol), LibLaunchPlan.toLower(tokenPlan.symbol)
                            )
                    ) {
                        outcome.failed = true;
                        outcome.failure =
                            abi.encodeWithSelector(DuplicateSymbol.selector, tokenPlan.symbol, all[j].metadataFile);
                    }
                }
            } catch (bytes memory failure) {
                outcome.failed = true;
                outcome.failure = failure;
            }
        }
        outcomes = new FileOutcome[](inputCount);
        for (uint256 i = 0; i < inputCount; i++) {
            outcomes[i] = all[i];
        }
    }

    /// @notice The lines `plan()` logs for a batch: an ignore line per path that
    /// is not a deploy input, a `FAIL` line per refusal, a skip line per
    /// shipped symbol, the plan lines per planned token, and
    /// `nothing to deploy` when no file is refused or planned.
    /// @param outcomes The batch's outcomes.
    /// @return lines The log lines, in order.
    /// @return failures How many files were refused.
    function describeOutcomes(FileOutcome[] memory outcomes)
        public
        pure
        returns (string[] memory lines, uint256 failures)
    {
        string[] memory all = new string[](outcomes.length * 2 + 1);
        uint256 lineCount = 0;
        uint256 planned = 0;
        for (uint256 i = 0; i < outcomes.length; i++) {
            FileOutcome memory outcome = outcomes[i];
            if (outcome.ignored) {
                all[lineCount++] = string.concat(
                    "  ignore ", printable(outcome.metadataFile), " (not a launch/metadata/<name>.json file)"
                );
            } else if (outcome.failed) {
                failures++;
                all[lineCount++] = describeFailureLine(outcome.metadataFile, outcome.failure);
            } else if (outcome.skipped) {
                all[lineCount++] = string.concat("  skip  ", outcome.metadataFile, " (already in the ledger)");
            } else {
                planned++;
                (string memory line, string memory dedicatedLine) = describePlan(outcome.plan);
                all[lineCount++] = line;
                if (bytes(dedicatedLine).length != 0) all[lineCount++] = dedicatedLine;
            }
        }
        if (failures == 0 && planned == 0) all[lineCount++] = "  nothing to deploy";
        lines = new string[](lineCount);
        for (uint256 i = 0; i < lineCount; i++) {
            lines[i] = all[i];
        }
    }

    /// @notice The `FAIL` line `plan()` logs for one file.
    /// @param file The refused metadata file.
    /// @param failure The revert data.
    /// @return The log line.
    function describeFailureLine(string memory file, bytes memory failure) public pure returns (string memory) {
        return string.concat("  FAIL  ", printable(file), " - ", describeFailure(failure));
    }

    /// @notice The plan line and, for a dedicated token, the authoriser line
    /// that `describeOutcomes` adds to the log. `dedicatedLine` is empty when
    /// the token uses the shared authoriser.
    /// @param tokenPlan The planned token.
    /// @return line The plan line.
    /// @return dedicatedLine The dedicated-authoriser line, or empty.
    function describePlan(TokenPlan memory tokenPlan)
        public
        pure
        returns (string memory line, string memory dedicatedLine)
    {
        line = string.concat(
            "  plan  ",
            tokenPlan.symbol,
            " \"",
            tokenPlan.name,
            "\" type=",
            tokenPlan.assetType == AssetType.Etf ? "etf" : "equity",
            " certify-until=",
            LibUtcDate.toIsoDate(tokenPlan.certifyUntil)
        );
        if (tokenPlan.dedicated) {
            dedicatedLine = string.concat(
                "        authorizer=",
                vm.toString(tokenPlan.landingAuthoriser),
                " (dedicated, minter ",
                vm.toString(tokenPlan.dedicatedMinter),
                tokenPlan.dedicatedMinterGrantPending ? ", grant pending)" : ")"
            );
        }
    }

    /// @notice `text` when every byte is printable ASCII, else its hex. Every
    /// file-sourced string goes through this before it reaches the job log,
    /// where a newline could start a workflow command.
    /// @param text The text.
    /// @return The text, or `0x` and its bytes in hex.
    function printable(string memory text) public pure returns (string memory) {
        bytes memory textBytes = bytes(text);
        for (uint256 i = 0; i < textBytes.length; i++) {
            if (textBytes[i] < 0x20 || textBytes[i] > 0x7E) return vm.toString(textBytes);
        }
        return text;
    }

    /// @notice A plan refusal in words, for the job log. Strings from the
    /// input files appear through `printable`.
    /// @param failure The revert data.
    /// @return The refusal in words; `unreadable` when the data is too short
    /// to name an error.
    function describeFailure(bytes memory failure) public pure returns (string memory) {
        if (failure.length < 4) return "unreadable";
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = bytes4(failure);
        bytes memory args = Bytes.slice(failure, 4);
        if (selector == bytes4(0x08c379a0)) return printable(abi.decode(args, (string)));
        if (selector == MissingPrimaryTicker.selector) return "primary_ticker is missing";
        if (selector == MissingName.selector) return "name is missing";
        if (selector == InvalidCounterparties.selector) {
            return "offchain_counterparties must be exactly the US set [AlpacaDB Inc, Clear Street LLC] or the non-US set"
                " [AlpacaDB Inc, Clear Street LLC, Freedom Finance] - pre-2026-08-19 files carry the retired set";
        }
        if (selector == InvalidTicker.selector) {
            return string.concat(
                "primary_ticker may hold only ASCII letters, digits, '.' and '-', got \"",
                printable(abi.decode(args, (string))),
                "\""
            );
        }
        if (selector == DuplicateSymbol.selector) {
            (string memory symbol, string memory firstFile) = abi.decode(args, (string, string));
            return string.concat(printable(symbol), " is also planned from ", printable(firstFile));
        }
        if (selector == UnsupportedAssetType.selector) {
            return string.concat(
                "asset_type must be \"Equity\" or \"ETF\", got \"", printable(abi.decode(args, (string))), "\""
            );
        }
        if (selector == NameIsTicker.selector) {
            return string.concat("name is the ticker (", printable(abi.decode(args, (string))), "), not the asset name");
        }
        if (selector == UnicodeWhitespaceInName.selector) {
            return string.concat("name holds Unicode whitespace: \"", printable(abi.decode(args, (string))), "\"");
        }
        if (selector == ControlCharacterInName.selector) {
            return string.concat("name holds a control character: ", printable(abi.decode(args, (string))));
        }
        if (selector == InvalidCountryIso.selector) {
            return
                string.concat(
                    "country.iso must be a 2-letter code, got \"", printable(abi.decode(args, (string))), "\""
                );
        }
        if (selector == InvalidIsin.selector) {
            return string.concat("isin is missing or malformed: \"", printable(abi.decode(args, (string))), "\"");
        }
        if (selector == OwnerNotAllowlisted.selector) {
            return string.concat(vm.toString(abi.decode(args, (address))), " is not an allowlisted owner");
        }
        if (selector == DedicatedPinWrongChain.selector) {
            (string memory symbol, uint256 chainId) = abi.decode(args, (string, uint256));
            return string.concat(
                printable(symbol), ": dedicated authoriser pin is for chainId ", vm.toString(chainId), ", not Base"
            );
        }
        if (selector == DedicatedAuthoriserUnset.selector) {
            (string memory symbol, string memory authoriser) = abi.decode(args, (string, string));
            return string.concat(
                printable(symbol),
                " requires a dedicated authoriser but none is pinned (got \"",
                printable(authoriser),
                "\")"
            );
        }
        if (selector == DedicatedAuthoriserIsShared.selector) {
            return
                string.concat(printable(abi.decode(args, (string))), ": dedicated authoriser is the shared authoriser");
        }
        if (selector == DedicatedMinterUnset.selector) {
            (string memory symbol, string memory minter) = abi.decode(args, (string, string));
            return
                string.concat(
                    printable(symbol), ": dedicated minter is unset or malformed: \"", printable(minter), "\""
                );
        }
        if (selector == DedicatedDeployBlockUnset.selector) {
            return string.concat(printable(abi.decode(args, (string))), ": dedicated authoriser deployBlock is unset");
        }
        if (selector == DedicatedAuthoriserNotAllowlisted.selector) {
            (string memory symbol, address authoriser) = abi.decode(args, (string, address));
            return string.concat(
                printable(symbol),
                ": dedicated authoriser ",
                vm.toString(authoriser),
                " is not allowlisted as authorizer on Base"
            );
        }
        return vm.toString(failure);
    }

    /// @notice `name`'s value, or `defaultPath` when unset. An override must
    /// be under `out/` and must not hold `..`.
    function _inputPath(string memory name, string memory defaultPath) internal view returns (string memory) {
        string memory path = vm.envOr(name, defaultPath);
        if (Strings.equal(path, defaultPath)) return path;
        bytes memory pathBytes = bytes(path);
        bool underOut = pathBytes.length > 4 && Strings.equal(string(Bytes.slice(pathBytes, 0, 4)), "out/");
        for (uint256 i = 0; underOut && i + 1 < pathBytes.length; i++) {
            underOut = pathBytes[i] != "." || pathBytes[i + 1] != ".";
        }
        if (!underOut) revert LaunchInputOutsideOut(name, path);
        return path;
    }

    /// @notice The plan file: `tokens` keyed by symbol, the input files, and
    /// the clock the certification dates were counted from. Foundry keeps
    /// serialized objects for the whole process, so both are reset first.
    function _planJson(FileOutcome[] memory outcomes, PlanInputs memory inputs, uint256 nowSeconds)
        internal
        returns (string memory)
    {
        string memory tokens = vm.serializeJson("tokens", "{}");
        vm.serializeJson("plan", "{}");
        for (uint256 i = 0; i < outcomes.length; i++) {
            if (outcomes[i].ignored || outcomes[i].skipped || outcomes[i].failed) continue;
            TokenPlan memory tokenPlan = outcomes[i].plan;
            string memory key = tokenPlan.symbol;
            vm.serializeJson(key, "{}");
            vm.serializeString(key, "metadataFile", tokenPlan.metadataFile);
            vm.serializeString(key, "symbol", tokenPlan.symbol);
            vm.serializeString(key, "name", tokenPlan.name);
            vm.serializeString(key, "type", tokenPlan.assetType == AssetType.Etf ? "etf" : "equity");
            vm.serializeUint(key, "certifyUntil", tokenPlan.certifyUntil);
            vm.serializeAddress(key, "intendedOwner", tokenPlan.intendedOwner);
            vm.serializeAddress(key, "landingAuthoriser", tokenPlan.landingAuthoriser);
            vm.serializeBool(key, "dedicated", tokenPlan.dedicated);
            vm.serializeAddress(key, "dedicatedMinter", tokenPlan.dedicatedMinter);
            vm.serializeUint(key, "dedicatedDeployBlock", tokenPlan.dedicatedDeployBlock);
            string memory token =
                vm.serializeBool(key, "dedicatedMinterGrantPending", tokenPlan.dedicatedMinterGrantPending);
            tokens = vm.serializeString("tokens", tokenPlan.symbol, token);
        }
        vm.serializeString("plan", "ledger", inputs.ledger);
        vm.serializeString("plan", "allowlist", inputs.allowlist);
        vm.serializeString("plan", "pins", inputs.pins);
        vm.serializeUint("plan", "plannedAt", nowSeconds);
        return vm.serializeString("plan", "tokens", tokens);
    }
}
