// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
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
import {LaunchFilePlanner} from "./lib/LaunchFilePlanner.sol";

/// @notice At least one metadata file failed its checks. Every failure is
/// logged before this reverts.
/// @param failures How many files failed.
error LaunchPlanInvalid(uint256 failures);

/// @notice Two files in one batch derive the same symbol. Launching both would
/// deploy the token twice.
error DuplicateSymbol(string symbol, string firstFile);

/// @title LaunchBaseTokens
/// @notice The Base token launch ported from sft-ops: `plan()` is its
/// `cd-plan`. Each `launch/metadata/<ticker>.json` named in `LAUNCH_FILES`
/// (space-separated) is checked and turned into launch arguments, written to
/// `LAUNCH_PLAN_OUT`. Inputs default to the committed files under `launch/`
/// and can be overridden by environment for tests.
contract LaunchBaseTokens is Script {
    string internal constant DEFAULT_LEDGER = "launch/launches.json";
    string internal constant DEFAULT_PINS = "launch/dedicated-authorisers.json";
    string internal constant DEFAULT_ALLOWLIST = "launch/allowlist.json";
    string internal constant DEFAULT_PLAN_OUT = "out/launch-plan.json";

    /// @notice One file's outcome, for the log and the plan file.
    struct FileOutcome {
        string metadataFile;
        bool skipped;
        bytes failure;
        TokenPlan plan;
    }

    function plan() external {
        string[] memory files = vm.envOr("LAUNCH_FILES", " ", new string[](0));
        uint256 nowSeconds = vm.envOr("LAUNCH_NOW", vm.unixTime() / 1000);
        PlanContext memory ctx = planContext(
            vm.envOr("LAUNCH_LEDGER", DEFAULT_LEDGER),
            vm.envOr("LAUNCH_ALLOWLIST", DEFAULT_ALLOWLIST),
            vm.envOr("LAUNCH_PINS", DEFAULT_PINS),
            nowSeconds
        );

        FileOutcome[] memory outcomes = planFiles(files, ctx);

        uint256 failures = 0;
        uint256 planned = 0;
        for (uint256 i = 0; i < outcomes.length; i++) {
            FileOutcome memory outcome = outcomes[i];
            if (outcome.failure.length != 0) {
                failures++;
                console2.log(describeFailureLine(outcome.metadataFile, outcome.failure));
            } else if (outcome.skipped) {
                console2.log("  skip ", outcome.metadataFile, "(already in the ledger)");
            } else {
                planned++;
                _logPlan(outcome.plan);
            }
        }
        if (failures != 0) revert LaunchPlanInvalid(failures);
        if (planned == 0) console2.log("  nothing to deploy");

        vm.writeJson(_planJson(outcomes, nowSeconds), vm.envOr("LAUNCH_PLAN_OUT", DEFAULT_PLAN_OUT));
    }

    /// @notice Everything the plan depends on besides the metadata files.
    function planContext(string memory ledger, string memory allowlist, string memory pins, uint256 nowSeconds)
        public
        view
        returns (PlanContext memory ctx)
    {
        ctx.shippedSymbols = LibLaunchInputs.readShippedSymbols(ledger);
        ctx.allowlistedOwners = LibLaunchInputs.readAllowlisted(allowlist, "owner", 0);
        ctx.allowlistedAuthorisers =
            LibLaunchInputs.readAllowlisted(allowlist, "authorizer", LibLaunchPlan.BASE_CHAIN_ID);
        ctx.pins = LibLaunchInputs.readPins(pins);
        ctx.ownerSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        ctx.sharedAuthoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        ctx.now = nowSeconds;
    }

    /// @notice Plan every deploy input in `files`; other paths are ignored.
    function planFiles(string[] memory files, PlanContext memory ctx) public returns (FileOutcome[] memory outcomes) {
        FileOutcome[] memory all = new FileOutcome[](files.length);
        LaunchFilePlanner planner = new LaunchFilePlanner();
        uint256 n = 0;
        for (uint256 i = 0; i < files.length; i++) {
            if (!LibLaunchInputs.isMetadataFile(files[i])) continue;
            all[n].metadataFile = files[i];
            try planner.planFile(files[i], ctx) returns (bool skipped, TokenPlan memory tokenPlan) {
                all[n].skipped = skipped;
                all[n].plan = tokenPlan;
                if (!skipped) {
                    for (uint256 j = 0; j < n; j++) {
                        if (
                            !all[j].skipped && all[j].failure.length == 0
                                && Strings.equal(
                                    LibLaunchPlan.toLower(all[j].plan.symbol), LibLaunchPlan.toLower(tokenPlan.symbol)
                                )
                        ) {
                            all[n].failure =
                                abi.encodeWithSelector(DuplicateSymbol.selector, tokenPlan.symbol, all[j].metadataFile);
                        }
                    }
                }
            } catch (bytes memory failure) {
                // An empty revert is still a refusal. `plan()` treats a zero-length
                // failure as success, so store the marker `describeFailure` already names.
                all[n].failure = failure.length == 0 ? bytes("unreadable") : failure;
            }
            n++;
        }
        outcomes = new FileOutcome[](n);
        for (uint256 i = 0; i < n; i++) {
            outcomes[i] = all[i];
        }
    }

    /// @notice The `FAIL` line `plan()` logs for one file.
    function describeFailureLine(string memory file, bytes memory failure) public pure returns (string memory) {
        return string.concat("  FAIL  ", file, " - ", describeFailure(failure));
    }

    /// @notice The lines `_logPlan` prints. `dedicatedLine` is empty when the
    /// token uses the shared authoriser.
    function describePlan(TokenPlan memory p) public pure returns (string memory line, string memory dedicatedLine) {
        line = string.concat(
            "  plan  ",
            p.symbol,
            " \"",
            p.name,
            "\" type=",
            p.assetType == AssetType.Etf ? "etf" : "equity",
            " certify-until=",
            LibUtcDate.toIsoDate(p.certifyUntil)
        );
        if (p.dedicated) {
            dedicatedLine = string.concat(
                "        authorizer=",
                vm.toString(p.landingAuthoriser),
                " (dedicated, minter ",
                vm.toString(p.dedicatedMinter),
                p.dedicatedMinterGrantPending ? ", grant pending)" : ")"
            );
        }
    }

    /// @notice A plan refusal in words, for the job log.
    function describeFailure(bytes memory failure) public pure returns (string memory) {
        if (failure.length < 4 || keccak256(failure) == keccak256(bytes("unreadable"))) return "unreadable";
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = bytes4(failure);
        bytes memory args = new bytes(failure.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = failure[i + 4];
        }
        if (selector == bytes4(0x08c379a0)) return abi.decode(args, (string));
        if (selector == MissingPrimaryTicker.selector) return "primary_ticker is missing";
        if (selector == MissingName.selector) return "name is missing";
        if (selector == InvalidCounterparties.selector) {
            return "offchain_counterparties must be exactly the US set [AlpacaDB Inc, Clear Street LLC] or the non-US set"
                " [AlpacaDB Inc, Clear Street LLC, Freedom Finance] - pre-2026-08-19 files carry the retired set";
        }
        if (selector == InvalidTicker.selector) {
            return string.concat(
                "primary_ticker may hold only ASCII letters, digits, '.' and '-', got \"",
                abi.decode(args, (string)),
                "\""
            );
        }
        if (selector == DuplicateSymbol.selector) {
            (string memory symbol, string memory firstFile) = abi.decode(args, (string, string));
            return string.concat(symbol, " is also planned from ", firstFile);
        }
        if (selector == UnsupportedAssetType.selector) {
            return string.concat("asset_type must be \"Equity\" or \"ETF\", got \"", abi.decode(args, (string)), "\"");
        }
        if (selector == NameIsTicker.selector) {
            return string.concat("name is the ticker (", abi.decode(args, (string)), "), not the asset name");
        }
        if (selector == InvalidCountryIso.selector) {
            return string.concat("country.iso must be a 2-letter code, got \"", abi.decode(args, (string)), "\"");
        }
        if (selector == InvalidIsin.selector) {
            return string.concat("isin is missing or malformed: \"", abi.decode(args, (string)), "\"");
        }
        if (selector == OwnerNotAllowlisted.selector) {
            return string.concat(vm.toString(abi.decode(args, (address))), " is not an allowlisted owner");
        }
        if (selector == DedicatedPinWrongChain.selector) {
            (string memory symbol, uint256 chainId) = abi.decode(args, (string, uint256));
            return
                string.concat(symbol, ": dedicated authoriser pin is for chainId ", vm.toString(chainId), ", not Base");
        }
        if (selector == DedicatedAuthoriserUnset.selector) {
            (string memory symbol, string memory authoriser) = abi.decode(args, (string, string));
            return
                string.concat(symbol, " requires a dedicated authoriser but none is pinned (got \"", authoriser, "\")");
        }
        if (selector == DedicatedAuthoriserIsShared.selector) {
            return string.concat(abi.decode(args, (string)), ": dedicated authoriser is the shared authoriser");
        }
        if (selector == DedicatedMinterUnset.selector) {
            (string memory symbol, string memory minter) = abi.decode(args, (string, string));
            return string.concat(symbol, ": dedicated minter is unset or malformed: \"", minter, "\"");
        }
        if (selector == DedicatedDeployBlockUnset.selector) {
            return string.concat(abi.decode(args, (string)), ": dedicated authoriser deployBlock is unset");
        }
        if (selector == DedicatedAuthoriserNotAllowlisted.selector) {
            (string memory symbol, address authoriser) = abi.decode(args, (string, address));
            return string.concat(
                symbol, ": dedicated authoriser ", vm.toString(authoriser), " is not allowlisted as authorizer on Base"
            );
        }
        return vm.toString(failure);
    }

    function _logPlan(TokenPlan memory p) internal pure {
        (string memory line, string memory dedicatedLine) = describePlan(p);
        console2.log(line);
        if (bytes(dedicatedLine).length != 0) console2.log(dedicatedLine);
    }

    /// @notice The plan file: `tokens` keyed by symbol, plus the clock the
    /// certification dates were counted from.
    function _planJson(FileOutcome[] memory outcomes, uint256 nowSeconds) internal returns (string memory) {
        string memory tokens = "{}";
        for (uint256 i = 0; i < outcomes.length; i++) {
            if (outcomes[i].skipped || outcomes[i].failure.length != 0) continue;
            TokenPlan memory p = outcomes[i].plan;
            string memory key = p.symbol;
            vm.serializeString(key, "metadataFile", p.metadataFile);
            vm.serializeString(key, "symbol", p.symbol);
            vm.serializeString(key, "name", p.name);
            vm.serializeString(key, "type", p.assetType == AssetType.Etf ? "etf" : "equity");
            vm.serializeUint(key, "certifyUntil", p.certifyUntil);
            vm.serializeAddress(key, "intendedOwner", p.intendedOwner);
            vm.serializeAddress(key, "landingAuthoriser", p.landingAuthoriser);
            vm.serializeBool(key, "dedicated", p.dedicated);
            vm.serializeAddress(key, "dedicatedMinter", p.dedicatedMinter);
            vm.serializeUint(key, "dedicatedDeployBlock", p.dedicatedDeployBlock);
            string memory token = vm.serializeBool(key, "dedicatedMinterGrantPending", p.dedicatedMinterGrantPending);
            tokens = vm.serializeString("tokens", p.symbol, token);
        }
        vm.serializeUint("plan", "plannedAt", nowSeconds);
        return vm.serializeString("plan", "tokens", tokens);
    }
}
