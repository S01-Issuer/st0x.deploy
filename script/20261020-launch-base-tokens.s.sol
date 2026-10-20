// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Bytes} from "@openzeppelin-contracts-5.7.0/utils/Bytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IAuthorizeV1} from "rain-vats-0.2.5/src/interface/IAuthorizeV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.5/src/interface/IReceiptVaultV3.sol";
import {
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.2.5/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.2.5/src/abstract/ReceiptVault.sol";
import {CERTIFY, DEPOSIT, WITHDRAW} from "rain-vats-0.2.5/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {CERTIFY_ADMIN} from "rain-vats-0.2.5/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {IStoxUnifiedDeployerV1} from "../src/interface/IStoxUnifiedDeployerV1.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibProdLaunchBase} from "../src/lib/LibProdLaunchBase.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
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
import {LibLaunchPayload, LaunchPayloads} from "./lib/LibLaunchPayload.sol";
import {LibLaunchStages, StageReceipt} from "./lib/LibLaunchStages.sol";
import {LibLedger, LedgerRow} from "./lib/LibLedger.sol";
import {LibRoleHistory} from "./lib/LibRoleHistory.sol";
import {LibTokenDeployment, ISetAuthorizer} from "./lib/LibTokenDeployment.sol";

/// @notice At least one metadata file failed its checks. Every failure is
/// logged before this reverts.
/// @param failures How many files failed.
error LaunchPlanInvalid(uint256 failures);

/// @notice Two files in one batch derive the same symbol. Launching both would
/// deploy the token twice.
error DuplicateSymbol(string symbol, string firstFile);

/// @notice An environment override of a launch input names a path outside
/// `out/`, or one holding `..`. Overrides exist for tests and the end-to-end
/// rehearsal, which stage their inputs there.
error LaunchInputOutsideOut(string name, string path);

/// @notice The script ran against a chain other than Base.
error WrongChain(uint256 chainId);

/// @notice A broadcasting stage ran as someone other than the launch signer.
/// st0x.deploy's own CI deploy key cannot launch.
error WrongSigner(address sender);

/// @notice `simulate` ran with `--broadcast`, which would send one batch of
/// pre-simulated addresses.
error SimulateCannotBroadcast();

/// @notice The symbol is not in the plan file.
error NotPlanned(string symbol);

/// @notice `prepare` has not written this token's payloads.
error PayloadsMissing(string symbol);

/// @notice The RPC has not yet reached the block the previous stage landed in.
/// Nothing was sent; the stage can be retried.
error StageNotReady(uint256 blockNumber, uint256 required);

/// @notice The stage's own work is already on chain, so running it again would
/// make a second vault or clone, or replay the wiring.
error StageAlreadyDone(string symbol, string stage);

/// @notice The `deploy` stage file holds no `Deployment` from the unified
/// deployer.
error DeploymentNotFound(string symbol);

/// @notice The `clone` stage file holds no `NewClone` from the clone factory.
error NewCloneNotFound(string symbol);

/// @notice The mined vault is not the planned token owned by the signer.
error VaultMismatch(address vault);

/// @notice The mined temp authoriser does not let the signer grant CERTIFY.
error TempAuthoriserNotSigners(address temp);

/// @notice The handoff target is not the production Safe allowlisted as
/// `owner` on Base.
error HandoffTargetNotAllowlisted(address owner);

/// @notice The plan's landing authoriser is not the shared authoriser for a
/// token without a pin, or not allowlisted as `authorizer` on Base for a
/// pinned one.
error LandingAuthoriserNotAllowed(address authoriser);

/// @notice The payloads carry test CIDs, which are never published unless
/// `LAUNCH_ALLOW_FIXED_CIDS` is set.
error FixedCidsNotAllowed(string symbol);

/// @notice The vault's certification expired, or never started.
error CertificationExpired(address vault);

/// @notice The dedicated authoriser has no code.
error DedicatedAuthoriserNoCode(address authoriser);

/// @notice The dedicated authoriser was not created at its pinned block, so
/// its role history cannot be proven complete.
error DedicatedAuthoriserNotCreatedAt(address authoriser, uint256 deployBlock);

/// @notice DEPOSIT or WITHDRAW on the dedicated authoriser is held by someone
/// other than its minter and the owner Safe, or its minter lacks it.
error DedicatedAuthoriserNotExclusive(string problems);

/// @notice The post-launch read-back failed for at least one recorded token.
error LaunchCheckFailed(string failures);

/// @dev rain-metadata's MetaBoard, which is not a dependency here.
interface IMetaBoard {
    function emitMeta(bytes32 subject, bytes calldata meta) external;
}

/// @dev The receipt-vault entrypoints the launch calls that rain-vats ships no
/// interface for.
interface ILaunchedVault {
    function receiptVaultInformation(bytes memory vaultInformation) external;
    function certify(uint256 certifyUntil, bool forceUntil, bytes calldata data) external;
    function isCertificationExpired() external view returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

/// @dev The clone factory sft-ops clones the temp authoriser from.
interface ICloneFactory {
    function clone(address implementation, bytes calldata data) external returns (address);
}

/// @title LaunchBaseTokens
/// @notice The Base token launch ported from sft-ops, step for step.
///
/// - `plan()` is `cd-plan`: each `launch/metadata/<ticker>.json` named in
///   `LAUNCH_FILES` (space-separated) is checked and turned into launch
///   arguments, written to the plan file.
/// - `prepare(symbol)` builds the schema and metadata documents, uploading
///   both to Pinata.
/// - `simulate(symbol)` runs the whole launch of one token on a fork, as
///   `create-sft`'s pre-flight does. It never broadcasts.
/// - `deploy`, `clone` and `wire` broadcast the launch in three stages. Each
///   address-creating transaction is its own invocation, and the next stage
///   reads the mined address from the previous stage's receipts (a copy of
///   forge's broadcast file under `LAUNCH_STAGE_DIR/<symbol>/`), as
///   `create-sft` reads each receipt before the next step.
/// - `record()` appends a ledger row for every token whose landing
///   authoriser was set, and `check()` is `cd-deploy`'s read-back.
///
/// Environment:
/// - `LAUNCH_FILES`: the changed files; paths that are not deploy inputs are
///   ignored. Default none.
/// - `LAUNCH_NOW`: unix seconds the certification year counts from. Default
///   the current time.
/// - `LAUNCH_LEDGER`, `LAUNCH_ALLOWLIST`, `LAUNCH_PINS`: the ledger, allowlist
///   and dedicated-authoriser pins. Default the committed files under
///   `launch/`.
/// - `LAUNCH_PLAN`: the plan file. Default `out/launch-plan.json`.
/// - `LAUNCH_STAGE_DIR`: where each token's stage files live. Required by the
///   broadcasting stages, so they read the receipts `launch/stage.sh` copies;
///   `out/launch` otherwise.
///
/// An override must be under `out/`.
contract LaunchBaseTokens is Script {
    string internal constant DEFAULT_LEDGER = "launch/launches.json";
    string internal constant DEFAULT_PINS = "launch/dedicated-authorisers.json";
    string internal constant DEFAULT_ALLOWLIST = "launch/allowlist.json";
    string internal constant DEFAULT_PLAN = "out/launch-plan.json";
    string internal constant DEFAULT_STAGE_DIR = "out/launch";

    /// @notice Where the launch reads and writes. `paths()` takes each from
    /// the environment, defaulting to the committed files; tests pass their
    /// own.
    struct LaunchPaths {
        string plan;
        string stageDir;
        string ledger;
        string allowlist;
    }

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
        LaunchPaths memory at = paths();
        PlanInputs memory inputs =
            PlanInputs({ledger: at.ledger, allowlist: at.allowlist, pins: _inputPath("LAUNCH_PINS", DEFAULT_PINS)});

        FileOutcome[] memory outcomes =
            planFiles(files, planContext(inputs.ledger, inputs.allowlist, inputs.pins, nowSeconds));

        (string[] memory lines, uint256 failures) = describeOutcomes(outcomes);
        for (uint256 i = 0; i < lines.length; i++) {
            console2.log(lines[i]);
        }
        if (failures != 0) revert LaunchPlanInvalid(failures);

        writePlan(outcomes, inputs, nowSeconds, at.plan);
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
                if (!skipped) {
                    for (uint256 j = 0; j + 1 < inputCount; j++) {
                        if (
                            !all[j].skipped && !all[j].failed
                                && Strings.equal(
                                    LibLaunchPlan.toLower(all[j].plan.symbol), LibLaunchPlan.toLower(tokenPlan.symbol)
                                )
                        ) {
                            outcome.failed = true;
                            outcome.failure =
                                abi.encodeWithSelector(DuplicateSymbol.selector, tokenPlan.symbol, all[j].metadataFile);
                        }
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
                all[lineCount++] =
                    string.concat("  ignore ", outcome.metadataFile, " (not a launch/metadata/<name>.json file)");
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
        return string.concat("  FAIL  ", file, " - ", describeFailure(failure));
    }

    /// @notice The lines `plan()` logs for a token. `dedicatedLine` is empty when the
    /// token uses the shared authoriser.
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

    /// @notice The launch's paths from the environment; see the contract
    /// NatSpec.
    /// @return The paths.
    function paths() public view returns (LaunchPaths memory) {
        return LaunchPaths({
            plan: _inputPath("LAUNCH_PLAN", DEFAULT_PLAN),
            stageDir: _inputPath("LAUNCH_STAGE_DIR", DEFAULT_STAGE_DIR),
            ledger: _inputPath("LAUNCH_LEDGER", DEFAULT_LEDGER),
            allowlist: _inputPath("LAUNCH_ALLOWLIST", DEFAULT_ALLOWLIST)
        });
    }

    function stageFile(LaunchPaths memory at, string memory symbol, string memory stage)
        public
        pure
        returns (string memory)
    {
        return string.concat(at.stageDir, "/", symbol, "/", stage, ".json");
    }

    /// @notice The plan `plan()` wrote for `symbol`.
    function plannedToken(LaunchPaths memory at, string memory symbol) public view returns (TokenPlan memory p) {
        string memory json = vm.readFile(at.plan);
        string memory key = string.concat("$.tokens['", symbol, "']");
        if (!vm.keyExistsJson(json, key)) revert NotPlanned(symbol);
        p.metadataFile = vm.parseJsonString(json, string.concat(key, ".metadataFile"));
        p.symbol = vm.parseJsonString(json, string.concat(key, ".symbol"));
        p.name = vm.parseJsonString(json, string.concat(key, ".name"));
        p.assetType = LibLaunchPlan.parseAssetType(
            Strings.equal(vm.parseJsonString(json, string.concat(key, ".type")), "etf") ? "ETF" : "Equity"
        );
        p.certifyUntil = vm.parseJsonUint(json, string.concat(key, ".certifyUntil"));
        p.intendedOwner = vm.parseJsonAddress(json, string.concat(key, ".intendedOwner"));
        p.landingAuthoriser = vm.parseJsonAddress(json, string.concat(key, ".landingAuthoriser"));
        p.dedicated = vm.parseJsonBool(json, string.concat(key, ".dedicated"));
        p.dedicatedMinter = vm.parseJsonAddress(json, string.concat(key, ".dedicatedMinter"));
        p.dedicatedDeployBlock = vm.parseJsonUint(json, string.concat(key, ".dedicatedDeployBlock"));
        p.dedicatedMinterGrantPending = vm.parseJsonBool(json, string.concat(key, ".dedicatedMinterGrantPending"));
    }

    function plannedOrder(LaunchPaths memory at) public view returns (string[] memory) {
        return vm.parseJsonStringArray(vm.readFile(at.plan), "$.order");
    }

    // =========================================================================
    // prepare / simulate
    // =========================================================================

    /// @notice Build the token's schema and metadata documents and write them,
    /// with their CIDs, to its `payloads.json`. Uploads both to Pinata, unless
    /// `LAUNCH_FIXED_SCHEMA_CID` and `LAUNCH_FIXED_METADATA_CID` are set, which
    /// only tests do. Needs `--ffi`.
    function prepare(string memory symbol) external {
        prepareStage(
            paths(),
            symbol,
            vm.envOr("LAUNCH_FIXED_SCHEMA_CID", string("")),
            vm.envOr("LAUNCH_FIXED_METADATA_CID", string(""))
        );
    }

    function prepareStage(
        LaunchPaths memory at,
        string memory symbol,
        string memory fixedSchemaCid,
        string memory fixedMetadataCid
    ) public {
        TokenPlan memory p = plannedToken(at, symbol);
        bool fixedCids = bytes(fixedSchemaCid).length != 0 || bytes(fixedMetadataCid).length != 0;
        LaunchPayloads memory payloads = fixedCids
            ? LibLaunchPayload.withCids(p.metadataFile, p.name, fixedSchemaCid, fixedMetadataCid)
            : LibLaunchPayload.upload(p.metadataFile, p.name);

        string memory key = string.concat("payloads-", symbol);
        vm.serializeBytes(key, "schemaMeta", payloads.schemaMeta);
        vm.serializeString(key, "schemaCid", payloads.schemaCid);
        vm.serializeBytes(key, "metadataMeta", payloads.metadataMeta);
        vm.serializeString(key, "metadataCid", payloads.metadataCid);
        string memory json = vm.serializeString(key, "mode", fixedCids ? "fixed-cids" : "uploaded");
        vm.createDir(string.concat(at.stageDir, "/", symbol), true);
        vm.writeJson(json, stageFile(at, symbol, "payloads"));
        console2.log(string.concat(symbol, " schema CID:   ", payloads.schemaCid));
        console2.log(string.concat(symbol, " metadata CID: ", payloads.metadataCid));
        if (fixedCids) console2.log("  (fixed CIDs: nothing was uploaded)");
    }

    function payloadsOf(LaunchPaths memory at, string memory symbol)
        public
        view
        returns (LaunchPayloads memory payloads)
    {
        string memory path = stageFile(at, symbol, "payloads");
        if (!vm.exists(path)) revert PayloadsMissing(symbol);
        string memory json = vm.readFile(path);
        payloads.schemaMeta = vm.parseJsonBytes(json, ".schemaMeta");
        payloads.schemaCid = vm.parseJsonString(json, ".schemaCid");
        payloads.metadataMeta = vm.parseJsonBytes(json, ".metadataMeta");
        payloads.metadataCid = vm.parseJsonString(json, ".metadataCid");
    }

    /// @notice The whole launch of one token on a fork, as the signer: steps 1
    /// to 8 and the handoff, with every pre-flight and post-state check. Never
    /// broadcasts.
    function simulate(string memory symbol) external {
        simulateStage(paths(), symbol);
    }

    function simulateStage(LaunchPaths memory at, string memory symbol) public {
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) || vm.isContext(VmSafe.ForgeContext.ScriptResume)) {
            revert SimulateCannotBroadcast();
        }
        requireBase();
        TokenPlan memory p = plannedToken(at, symbol);
        LaunchPayloads memory payloads = payloadsOf(at, symbol);
        checkHandoffTarget(at, p);
        checkLandingAuthoriser(at, p);
        if (p.dedicated) checkDedicatedAuthoriser(p);

        vm.startPrank(LibProdLaunchBase.LAUNCH_SIGNER, LibProdLaunchBase.LAUNCH_SIGNER);
        (address vault, address wrapper) = deployToken(p);
        address temp = cloneTempAuthoriser(p.symbol);
        wireToken(p, vault, wrapper, temp, payloads);
        vm.stopPrank();

        assertLaunched(p, vault, temp);
        console2.log(string.concat(symbol, " simulated: vault ", vm.toString(vault), " wrapper ", vm.toString(wrapper)));
    }

    // =========================================================================
    // Staged broadcast
    // =========================================================================

    /// @notice Stage 1: deploy the vault and its wrapper.
    function deploy(string memory symbol) external {
        deployStage(paths(), symbol);
    }

    function deployStage(LaunchPaths memory at, string memory symbol) public {
        requireBase();
        requireSigner(msg.sender);
        TokenPlan memory p = plannedToken(at, symbol);
        (bool deployed,,,) = LibLaunchStages.findDeployment(
            LibLaunchStages.readReceipts(stageFile(at, symbol, "deploy")), unifiedDeployer()
        );
        if (deployed) revert StageAlreadyDone(symbol, "deploy");

        startLaunchBroadcast();
        IStoxUnifiedDeployerV1(unifiedDeployer()).newTokenAndWrapperVault(vaultConfig(p));
        stopLaunchBroadcast();
    }

    /// @notice Stage 2: clone the temp authoriser, once the mined vault from
    /// stage 1 is confirmed to be the planned token.
    function clone(string memory symbol) external {
        cloneStage(paths(), symbol);
    }

    function cloneStage(LaunchPaths memory at, string memory symbol) public {
        requireBase();
        requireSigner(msg.sender);
        TokenPlan memory p = plannedToken(at, symbol);
        (address vault,, uint256 deployedAt) = minedDeployment(at, symbol);
        if (block.number < deployedAt) revert StageNotReady(block.number, deployedAt);
        (bool cloned,,) = LibLaunchStages.findClone(
            LibLaunchStages.readReceipts(stageFile(at, symbol, "clone")), LibProdLaunchBase.CLONE_FACTORY
        );
        if (cloned) revert StageAlreadyDone(symbol, "clone");
        checkMinedVault(p, vault);

        startLaunchBroadcast();
        ICloneFactory(LibProdLaunchBase.CLONE_FACTORY).clone(tempAuthoriserImplementation(), tempAuthoriserConfig());
        stopLaunchBroadcast();
    }

    /// @notice Stage 3: steps 3 to 8 and the handoff, against the mined vault
    /// and temp authoriser. None of these create an address, so what lands is
    /// what this invocation simulated.
    function wire(string memory symbol) external {
        wireStage(paths(), symbol);
    }

    function wireStage(LaunchPaths memory at, string memory symbol) public {
        requireBase();
        requireSigner(msg.sender);
        TokenPlan memory p = plannedToken(at, symbol);
        LaunchPayloads memory payloads = payloadsOf(at, symbol);
        (address vault, address wrapper,) = minedDeployment(at, symbol);
        (bool cloned, address temp, uint256 clonedAt) = LibLaunchStages.findClone(
            LibLaunchStages.readReceipts(stageFile(at, symbol, "clone")), LibProdLaunchBase.CLONE_FACTORY
        );
        if (!cloned) revert NewCloneNotFound(symbol);
        if (block.number < clonedAt) revert StageNotReady(block.number, clonedAt);
        if (ISetAuthorizer(vault).authorizer() != vault) revert StageAlreadyDone(symbol, "wire");
        checkMinedVault(p, vault);
        if (!IAccessControl(temp).hasRole(CERTIFY_ADMIN, LibProdLaunchBase.LAUNCH_SIGNER)) {
            revert TempAuthoriserNotSigners(temp);
        }
        checkHandoffTarget(at, p);
        checkLandingAuthoriser(at, p);
        if (p.dedicated) checkDedicatedAuthoriser(p);
        if (
            Strings.equal(vm.parseJsonString(vm.readFile(stageFile(at, symbol, "payloads")), ".mode"), "fixed-cids")
                && !vm.envOr("LAUNCH_ALLOW_FIXED_CIDS", false)
        ) revert FixedCidsNotAllowed(symbol);

        startLaunchBroadcast();
        wireToken(p, vault, wrapper, temp, payloads);
        stopLaunchBroadcast();

        assertLaunched(p, vault, temp);
    }

    // =========================================================================
    // record / check
    // =========================================================================

    /// @notice Append a ledger row for every planned token whose landing
    /// authoriser is set: `create-sft` appends after that step, before the
    /// handoff. Tokens that stopped earlier are listed in
    /// `LAUNCH_STAGE_DIR/summary.md`. Runs on Base so the vault's state is read
    /// from the chain. Refuses an RPC behind the mined wire receipts.
    function record() external {
        requireBase();
        recordStage(paths(), LibUtcDate.toIsoDateTimeMs(vm.unixTime()));
    }

    function recordStage(LaunchPaths memory at, string memory deployedAt) public {
        string[] memory order = plannedOrder(at);
        LedgerRow[] memory rows = new LedgerRow[](order.length);
        uint256 n = 0;
        string memory summary = "";
        for (uint256 i = 0; i < order.length; i++) {
            TokenPlan memory p = plannedToken(at, order[i]);
            (bool landed, LedgerRow memory row, string memory stopped) = recordedRow(at, p, deployedAt);
            if (landed) {
                rows[n++] = row;
                summary = string.concat(summary, "- ", p.symbol, " ", vm.toString(row.sft));
                summary = string.concat(summary, ": recorded, owner ", vm.toString(row.currentOwner), "\n");
            } else {
                summary = string.concat(summary, "- ", p.symbol, ": ", stopped, "\n");
            }
        }
        assembly ("memory-safe") {
            mstore(rows, n)
        }
        LibLedger.append(at.ledger, rows);
        vm.createDir(at.stageDir, true);
        vm.writeFile(string.concat(at.stageDir, "/summary.md"), summary);
        console2.log(summary);
    }

    /// @notice The ledger row for `p`, when its landing authoriser was set,
    /// or the stage it stopped at.
    function recordedRow(LaunchPaths memory at, TokenPlan memory p, string memory deployedAt)
        public
        view
        returns (bool landed, LedgerRow memory row, string memory stopped)
    {
        string memory deployFile = stageFile(at, p.symbol, "deploy");
        (bool deployed, address vault, address wrapper,) =
            LibLaunchStages.findDeployment(LibLaunchStages.readReceipts(deployFile), unifiedDeployer());
        if (!deployed) {
            string[] memory pending = LibLaunchStages.pendingHashes(deployFile);
            if (pending.length == 0) return (landed, row, "not deployed");
            return (landed, row, string.concat("deploy sent with no receipt, reconcile on chain: ", pending[0]));
        }
        (bool landingSet, bool handedOff) = launchProgress(at, p, vault);
        if (!landingSet) {
            return (
                landed,
                row,
                string.concat("vault ", vm.toString(vault), " stopped before its landing authoriser was set")
            );
        }
        row.symbol = p.symbol;
        row.name = p.name;
        row.sft = vault;
        row.wrapper = wrapper;
        row.authorizer = p.landingAuthoriser;
        row.chainId = LibLaunchPlan.BASE_CHAIN_ID;
        row.deployedAt = deployedAt;
        row.deployedBy = LibProdLaunchBase.LAUNCH_SIGNER;
        row.intendedOwner = p.intendedOwner;
        row.currentOwner = handedOff ? p.intendedOwner : LibProdLaunchBase.LAUNCH_SIGNER;
        row.certifyUntil = LibUtcDate.toIsoDateTimeMs(p.certifyUntil * 1000);
        landed = true;
        return (landed, row, "");
    }

    /// @notice Whether the vault's landing authoriser is set, and whether it
    /// was handed to its owner. Mined receipts retain landed progress, and
    /// chain state also counts when a transaction's receipt was not saved.
    function launchProgress(LaunchPaths memory at, TokenPlan memory p, address vault)
        internal
        view
        returns (bool landingSet, bool handedOff)
    {
        StageReceipt[] memory wired = LibLaunchStages.readReceipts(stageFile(at, p.symbol, "wire"));
        for (uint256 i = 0; i < wired.length; i++) {
            if (wired[i].blockNumber > block.number) revert StageNotReady(block.number, wired[i].blockNumber);
        }
        landingSet = LibLaunchStages.setAuthorizerLanded(wired, vault, p.landingAuthoriser);
        handedOff = LibLaunchStages.ownershipTransferred(wired, vault, p.intendedOwner);
        if (vault.code.length != 0) {
            landingSet = landingSet || ISetAuthorizer(vault).authorizer() == p.landingAuthoriser;
            handedOff = handedOff || Ownable(vault).owner() == p.intendedOwner;
        }
    }

    /// @notice `cd-deploy`'s read-back of every recorded token: owner is the
    /// Safe, the authoriser is the landing one, certification is live.
    function check() external view {
        checkStage(paths());
    }

    function checkStage(LaunchPaths memory at) public view {
        string[] memory order = plannedOrder(at);
        string memory failures = "";
        for (uint256 i = 0; i < order.length; i++) {
            TokenPlan memory p = plannedToken(at, order[i]);
            (bool landed, LedgerRow memory row,) = recordedRow(at, p, "");
            if (!landed) continue;
            address owner = Ownable(row.sft).owner();
            address authoriser = ISetAuthorizer(row.sft).authorizer();
            if (owner != p.intendedOwner) {
                failures = string.concat(failures, p.symbol, ": owner() is ", vm.toString(owner), "; ");
            }
            if (authoriser != p.landingAuthoriser) {
                failures = string.concat(failures, p.symbol, ": authorizer() is ", vm.toString(authoriser), "; ");
            }
            if (ILaunchedVault(row.sft).isCertificationExpired()) {
                failures = string.concat(failures, p.symbol, ": certification is expired; ");
            }
        }
        if (bytes(failures).length != 0) revert LaunchCheckFailed(failures);
    }

    // =========================================================================
    // Steps
    // =========================================================================

    function unifiedDeployer() public pure returns (address) {
        return LibProdDeployV1.STOX_UNIFIED_DEPLOYER;
    }

    /// @notice Step 1: `newTokenAndWrapperVault` with the signer as initial
    /// admin, the pair read from the `Deployment` event.
    function vaultConfig(TokenPlan memory p) internal pure returns (OffchainAssetReceiptVaultConfigV2 memory) {
        return OffchainAssetReceiptVaultConfigV2({
            initialAdmin: LibProdLaunchBase.LAUNCH_SIGNER,
            receiptVaultConfig: ReceiptVaultConfigV2({
                asset: address(0), name: p.name, symbol: p.symbol, receipt: address(0)
            })
        });
    }

    function tempAuthoriserImplementation() internal pure returns (address) {
        return LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
    }

    /// @notice `abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: signer}))`.
    function tempAuthoriserConfig() internal pure returns (bytes memory) {
        return abi.encode(LibProdLaunchBase.LAUNCH_SIGNER);
    }

    function deployToken(TokenPlan memory p) internal returns (address vault, address wrapper) {
        vm.recordLogs();
        IStoxUnifiedDeployerV1(unifiedDeployer()).newTokenAndWrapperVault(vaultConfig(p));
        (vault, wrapper) = LibTokenDeployment.readDeployment(vm.getRecordedLogs(), unifiedDeployer(), p.symbol);
    }

    /// @notice Step 2: a throwaway authoriser administered by the signer, only
    /// for the certification.
    function cloneTempAuthoriser(string memory symbol) internal returns (address temp) {
        vm.recordLogs();
        ICloneFactory(LibProdLaunchBase.CLONE_FACTORY).clone(tempAuthoriserImplementation(), tempAuthoriserConfig());
        StageReceipt[] memory asReceipt = new StageReceipt[](1);
        asReceipt[0] = LibLaunchStages.fromRecordedLogs(vm.getRecordedLogs(), block.number);
        bool found;
        (found, temp,) = LibLaunchStages.findClone(asReceipt, LibProdLaunchBase.CLONE_FACTORY);
        if (!found) revert NewCloneNotFound(symbol);
    }

    /// @notice Steps 3 to 8, then the handoff to the owner Safe.
    function wireToken(TokenPlan memory p, address vault, address wrapper, address temp, LaunchPayloads memory payloads)
        internal
    {
        ISetAuthorizer(vault).setAuthorizer(IAuthorizeV1(temp));
        ILaunchedVault(vault).receiptVaultInformation(payloads.schemaMeta);
        IMetaBoard(LibProdLaunchBase.METABOARD).emitMeta(bytes32(uint256(uint160(vault))), payloads.metadataMeta);
        IMetaBoard(LibProdLaunchBase.METABOARD).emitMeta(bytes32(uint256(uint160(wrapper))), payloads.metadataMeta);
        IAccessControl(temp).grantRole(CERTIFY, LibProdLaunchBase.LAUNCH_SIGNER);
        ILaunchedVault(vault).certify(p.certifyUntil, false, "");
        ISetAuthorizer(vault).setAuthorizer(IAuthorizeV1(p.landingAuthoriser));
        Ownable(vault).transferOwnership(p.intendedOwner);
    }

    // =========================================================================
    // Checks
    // =========================================================================

    function requireBase() internal view {
        if (block.chainid != LibLaunchPlan.BASE_CHAIN_ID) revert WrongChain(block.chainid);
    }

    function requireSigner(address sender) internal view virtual {
        if (sender != LibProdLaunchBase.LAUNCH_SIGNER) revert WrongSigner(sender);
    }

    function startLaunchBroadcast() internal virtual {
        vm.startBroadcast(LibProdLaunchBase.LAUNCH_SIGNER);
    }

    function stopLaunchBroadcast() internal virtual {
        vm.stopBroadcast();
    }

    /// @notice The pair stage 1 mined for `symbol`.
    function minedDeployment(LaunchPaths memory at, string memory symbol)
        internal
        view
        returns (address vault, address wrapper, uint256 blockNumber)
    {
        bool found;
        (found, vault, wrapper, blockNumber) = LibLaunchStages.findDeployment(
            LibLaunchStages.readReceipts(stageFile(at, symbol, "deploy")), unifiedDeployer()
        );
        if (!found) revert DeploymentNotFound(symbol);
    }

    /// @notice The mined vault is the planned token and still the signer's.
    function checkMinedVault(TokenPlan memory p, address vault) internal view {
        if (
            vault.code.length == 0 || !Strings.equal(ILaunchedVault(vault).name(), p.name)
                || !Strings.equal(ILaunchedVault(vault).symbol(), p.symbol)
                || Ownable(vault).owner() != LibProdLaunchBase.LAUNCH_SIGNER
        ) revert VaultMismatch(vault);
    }

    /// @notice `transfer-ownership`'s guard: the new owner is the production
    /// Safe, allowlisted as `owner` on Base.
    function checkHandoffTarget(LaunchPaths memory at, TokenPlan memory p) public view {
        address[] memory owners = LibLaunchInputs.readAllowlisted(at.allowlist, "owner", LibLaunchPlan.BASE_CHAIN_ID);
        if (
            p.intendedOwner != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE
                || !LibLaunchPlan.containsAddress(owners, p.intendedOwner)
        ) revert HandoffTargetNotAllowlisted(p.intendedOwner);
    }

    /// @notice The plan file cannot route a token anywhere `plan()` would not:
    /// the shared authoriser without a pin, an allowlisted one with a pin.
    function checkLandingAuthoriser(LaunchPaths memory at, TokenPlan memory p) public view {
        if (!p.dedicated) {
            if (p.landingAuthoriser != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE) {
                revert LandingAuthoriserNotAllowed(p.landingAuthoriser);
            }
            return;
        }
        address[] memory authorisers =
            LibLaunchInputs.readAllowlisted(at.allowlist, "authorizer", LibLaunchPlan.BASE_CHAIN_ID);
        if (
            p.landingAuthoriser == LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE
                || !LibLaunchPlan.containsAddress(authorisers, p.landingAuthoriser)
        ) revert LandingAuthoriserNotAllowed(p.landingAuthoriser);
    }

    /// @notice A dedicated authoriser exists, was created at its pinned block,
    /// and DEPOSIT and WITHDRAW on it are held only by its minter and the owner
    /// Safe: replayed from every role event since creation, and agreeing with
    /// `hasRole`. The minter must hold both unless its grants are pending. The
    /// shared-fleet depositors must not hold DEPOSIT.
    function checkDedicatedAuthoriser(TokenPlan memory p) public {
        address authoriser = p.landingAuthoriser;
        if (authoriser.code.length == 0) revert DedicatedAuthoriserNoCode(authoriser);
        if (!createdAt(authoriser, p.dedicatedDeployBlock)) {
            revert DedicatedAuthoriserNotCreatedAt(authoriser, p.dedicatedDeployBlock);
        }

        string memory problems = "";
        IAccessControl roles = IAccessControl(authoriser);
        address[2] memory fleet =
            [LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, LibProdDeployV4.ST0X_ORCHESTRATOR_INSTANCE];
        for (uint256 i = 0; i < fleet.length; i++) {
            if (roles.hasRole(DEPOSIT, fleet[i])) {
                problems = string.concat(problems, "shared-fleet depositor ", vm.toString(fleet[i]), " holds DEPOSIT; ");
            }
        }

        Vm.EthGetLogs[] memory history = LibRoleHistory.readLogs(authoriser, p.dedicatedDeployBlock, block.number);
        bytes32[2] memory guarded = [DEPOSIT, WITHDRAW];
        string[2] memory labels = ["DEPOSIT", "WITHDRAW"];
        for (uint256 r = 0; r < guarded.length; r++) {
            address[] memory holders = LibRoleHistory.holders(history, guarded[r]);
            problems = string.concat(
                problems,
                LibRoleHistory.exclusivityProblems(
                    labels[r],
                    holders,
                    p.dedicatedMinter,
                    LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
                    !p.dedicatedMinterGrantPending
                )
            );
            for (uint256 i = 0; i < holders.length; i++) {
                if (!roles.hasRole(guarded[r], holders[i])) {
                    problems = string.concat(
                        problems,
                        labels[r],
                        ": history says ",
                        vm.toString(holders[i]),
                        " holds it but hasRole() disagrees; "
                    );
                }
            }
            if (
                !LibLaunchPlan.containsAddress(holders, p.dedicatedMinter)
                    && roles.hasRole(guarded[r], p.dedicatedMinter)
            ) {
                problems = string.concat(
                    problems, labels[r], ": hasRole() says the minter holds it but history disagrees; "
                );
            }
        }
        if (bytes(problems).length != 0) revert DedicatedAuthoriserNotExclusive(problems);
    }

    /// @notice Whether `account` has no code before `blockNumber` and has code
    /// at it: it was created in that block, so no role event predates it.
    /// sft-ops proves the same with a `NewClone` log from any emitter in that
    /// block; forge's log cheatcode needs an emitter, so the code is compared
    /// instead. Needs an archive RPC.
    function createdAt(address account, uint256 blockNumber) internal returns (bool) {
        if (blockNumber == 0) return false;
        bytes memory before = vm.rpc(
            "eth_getCode", string.concat("[\"", vm.toString(account), "\",\"", hexQuantity(blockNumber - 1), "\"]")
        );
        bytes memory at =
            vm.rpc("eth_getCode", string.concat("[\"", vm.toString(account), "\",\"", hexQuantity(blockNumber), "\"]"));
        return before.length == 0 && at.length != 0;
    }

    /// @notice `create-sft`'s post-state: wired to the landing authoriser,
    /// owned by the Safe, certified, with CERTIFY granted on the temp
    /// authoriser.
    function assertLaunched(TokenPlan memory p, address vault, address temp) internal view {
        LibTokenDeployment.assertHandoffLanded(vault, p.landingAuthoriser, p.intendedOwner);
        if (ILaunchedVault(vault).isCertificationExpired()) revert CertificationExpired(vault);
        if (!IAccessControl(temp).hasRole(CERTIFY, LibProdLaunchBase.LAUNCH_SIGNER)) {
            revert TempAuthoriserNotSigners(temp);
        }
    }

    /// @notice A JSON-RPC quantity: `0x` and hex with no leading zeros.
    function hexQuantity(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0x0";
        bytes memory digits = new bytes(64);
        uint256 n = 0;
        while (value != 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 nibble = uint8(value & 0xf);
            digits[63 - n] = nibble < 10 ? bytes1(nibble + 0x30) : bytes1(nibble + 0x57);
            value >>= 4;
            n++;
        }
        bytes memory out = new bytes(n + 2);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < n; i++) {
            out[2 + i] = digits[64 - n + i];
        }
        return string(out);
    }

    /// @notice A plan refusal in words, for the job log.
    /// @param failure The revert data.
    /// @return The refusal in words; `unreadable` when the data is too short
    /// to name an error.
    function describeFailure(bytes memory failure) public pure returns (string memory) {
        if (failure.length < 4) return "unreadable";
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = bytes4(failure);
        bytes memory args = Bytes.slice(failure, 4);
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
        if (selector == UnicodeWhitespaceInName.selector) {
            return string.concat("name holds Unicode whitespace: \"", abi.decode(args, (string)), "\"");
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

    /// @notice Write the plan file for `outcomes`.
    /// @param outcomes The batch's outcomes.
    /// @param inputs The input files the plan was made from.
    /// @param nowSeconds The clock the certification dates were counted from.
    /// @param path The plan file.
    function writePlan(FileOutcome[] memory outcomes, PlanInputs memory inputs, uint256 nowSeconds, string memory path)
        public
    {
        vm.writeJson(_planJson(outcomes, inputs, nowSeconds), path);
    }

    /// @notice The plan file: `tokens` keyed by symbol, `order` in launch
    /// order, the input files, and the clock the certification dates were
    /// counted from. Foundry keeps serialized objects for the whole process, so
    /// both are reset first.
    function _planJson(FileOutcome[] memory outcomes, PlanInputs memory inputs, uint256 nowSeconds)
        internal
        returns (string memory)
    {
        string memory tokens = vm.serializeJson("tokens", "{}");
        vm.serializeJson("plan", "{}");
        string[] memory symbols = new string[](outcomes.length);
        uint256 plannedCount = 0;
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
            symbols[plannedCount++] = tokenPlan.symbol;
        }
        string[] memory order = new string[](plannedCount);
        for (uint256 i = 0; i < plannedCount; i++) {
            order[i] = symbols[i];
        }
        vm.serializeString("plan", "order", order);
        vm.serializeString("plan", "ledger", inputs.ledger);
        vm.serializeString("plan", "allowlist", inputs.allowlist);
        vm.serializeString("plan", "pins", inputs.pins);
        vm.serializeUint("plan", "plannedAt", nowSeconds);
        return vm.serializeString("plan", "tokens", tokens);
    }
}
