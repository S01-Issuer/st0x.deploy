// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    LaunchBaseTokens,
    WrongChain,
    WrongSigner,
    NotPlanned,
    PayloadsMissing,
    StageNotReady,
    StageAlreadyDone,
    DeploymentNotFound,
    NewCloneNotFound,
    HandoffTargetNotAllowlisted,
    LandingAuthoriserNotAllowed,
    VaultMismatch,
    TempAuthoriserNotSigners,
    CertifyNotGranted,
    FixedCidsNotAllowed,
    CertificationExpired,
    LaunchCheckFailed,
    StageSentUnconfirmed,
    StageDirUnset
} from "../../script/20261020-launch-base-tokens.s.sol";
import {CERTIFY_ADMIN} from "rain-vats-0.2.5/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {CERTIFY} from "rain-vats-0.2.5/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {OwnershipHandoffFailed, AuthoriserNotWired} from "../../script/lib/LibTokenDeployment.sol";
import {LibLedger, LedgerRow, LedgerNotAnArray} from "../../script/lib/LibLedger.sol";
import {LibLaunchStages, StageReceipt} from "../../script/lib/LibLaunchStages.sol";
import {LibRoleHistory} from "../../script/lib/LibRoleHistory.sol";
import {LibProdLaunchBase} from "../../src/lib/LibProdLaunchBase.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {TokenPlan} from "../../src/lib/LibLaunchPlan.sol";
import {LibTestLaunchStages} from "../lib/LibTestLaunchStages.sol";
import {LaunchBaseTokensHarness} from "./LaunchBaseTokensHarness.sol";

/// @title LaunchBaseTokensTest
/// @notice The staged launch's refusals, its reading of stage files and its
/// ledger rows, with no fork. Each test works in its own directory under
/// `out/`, because tests run in parallel.
contract LaunchBaseTokensTest is Test {
    address constant SIGNER = 0x21Cc8a5fe957a167cB92F12F4E658d755b00Be53;
    address constant SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;
    address constant SHARED = 0x315b16faa6eE413faBCa877d3851B3818369f0cD;
    address constant VAULT = address(0x7A01);
    address constant WRAPPER = address(0x7A02);
    address constant TEMP = address(0x7A03);
    uint256 constant NOW = 1792079467;

    LaunchBaseTokens internal script;
    LaunchBaseTokensHarness internal harness;

    function setUp() external {
        script = new LaunchBaseTokens();
        harness = new LaunchBaseTokensHarness();
    }

    function _writePlan(LaunchBaseTokens.LaunchPaths memory at, string memory metadataFile, uint256 nowSeconds)
        internal
    {
        string[] memory files = new string[](1);
        files[0] = metadataFile;
        LaunchBaseTokens.PlanInputs memory inputs = LaunchBaseTokens.PlanInputs({
            ledger: at.ledger, allowlist: at.allowlist, pins: "launch/dedicated-authorisers.json"
        });
        script.writePlan(
            script.planFiles(files, script.planContext(inputs.ledger, inputs.allowlist, inputs.pins, nowSeconds)),
            inputs,
            nowSeconds,
            at.plan
        );
    }

    /// @notice A fresh working directory with a plan for tDIS.
    function _paths(string memory name) internal returns (LaunchBaseTokens.LaunchPaths memory at) {
        string memory dir = string.concat("out/test-launch-unit-", name);
        if (vm.exists(dir)) vm.removeDir(dir, true);
        vm.createDir(string.concat(dir, "/stages/tDIS"), true);
        at = LaunchBaseTokens.LaunchPaths({
            plan: string.concat(dir, "/plan.json"),
            stageDir: string.concat(dir, "/stages"),
            ledger: string.concat(dir, "/launches.json"),
            allowlist: "launch/allowlist.json"
        });
        vm.writeFile(at.ledger, "[]\n");
        _writePlan(at, "launch/metadata/dis.json", NOW);
    }

    function _log(address emitter, bytes32 topic, bytes memory data) internal pure returns (Vm.Log memory log) {
        log.emitter = emitter;
        log.topics = new bytes32[](1);
        log.topics[0] = topic;
        log.data = data;
    }

    function _deployment(LaunchBaseTokens.LaunchPaths memory at, uint256 blockNumber) internal {
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _log(
            LibProdDeployV1.STOX_UNIFIED_DEPLOYER, LibLaunchStages.DEPLOYMENT_TOPIC, abi.encode(SIGNER, VAULT, WRAPPER)
        );
        LibTestLaunchStages.write(script.stageFile(at, "tDIS", "deploy"), logs, blockNumber, true);
    }

    function _clone(LaunchBaseTokens.LaunchPaths memory at, uint256 blockNumber) internal {
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _log(
            LibProdLaunchBase.CLONE_FACTORY, LibLaunchStages.NEW_CLONE_TOPIC, abi.encode(SIGNER, address(1), TEMP)
        );
        LibTestLaunchStages.write(script.stageFile(at, "tDIS", "clone"), logs, blockNumber, true);
    }

    function _wire(LaunchBaseTokens.LaunchPaths memory at, bool handedOff, bool success) internal {
        Vm.Log[] memory logs = new Vm.Log[](handedOff ? 2 : 1);
        logs[0] = _log(VAULT, LibLaunchStages.AUTHORIZER_SET_TOPIC, abi.encode(SIGNER, SHARED));
        if (handedOff) {
            logs[1].emitter = VAULT;
            logs[1].topics = new bytes32[](3);
            logs[1].topics[0] = LibLaunchStages.OWNERSHIP_TRANSFERRED_TOPIC;
            logs[1].topics[1] = bytes32(uint256(uint160(SIGNER)));
            logs[1].topics[2] = bytes32(uint256(uint160(SAFE)));
        }
        LibTestLaunchStages.write(script.stageFile(at, "tDIS", "wire"), logs, 1, success);
    }

    // Refusals

    function testStagesRefuseAChainOtherThanBase() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("chain");
        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, block.chainid));
        script.deployStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, block.chainid));
        script.simulateStage(at, "tDIS");
    }

    /// @notice st0x.deploy's own CI deploy key, or anyone else, cannot launch.
    function testStagesRefuseAnyoneButTheLaunchSigner() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("signer");
        vm.chainId(8453);
        address ciKey = address(0xC1);
        vm.startPrank(ciKey);
        vm.expectRevert(abi.encodeWithSelector(WrongSigner.selector, ciKey));
        script.deployStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(WrongSigner.selector, ciKey));
        script.cloneStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(WrongSigner.selector, ciKey));
        script.wireStage(at, "tDIS");
        vm.stopPrank();
    }

    function testStagesRefuseAnUnplannedSymbol() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("unplanned");
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSelector(NotPlanned.selector, "tWMT"));
        harness.deployStage(at, "tWMT");
    }

    function testDeployRefusesWhenItsDeploymentAlreadyLanded() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("redeploy");
        vm.chainId(8453);
        _payloads(at, "uploaded");
        _deployment(at, 1);
        vm.expectRevert(abi.encodeWithSelector(StageAlreadyDone.selector, "tDIS", "deploy"));
        harness.deployStage(at, "tDIS");
    }

    function testCloneRefusesWithoutAMinedDeployment() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("no-deployment");
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSelector(DeploymentNotFound.selector, "tDIS"));
        harness.cloneStage(at, "tDIS");
    }

    /// @notice A failed receipt's logs are not a deployment.
    function testCloneIgnoresAFailedDeployReceipt() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("failed-deploy");
        vm.chainId(8453);
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _log(
            LibProdDeployV1.STOX_UNIFIED_DEPLOYER, LibLaunchStages.DEPLOYMENT_TOPIC, abi.encode(SIGNER, VAULT, WRAPPER)
        );
        LibTestLaunchStages.write(script.stageFile(at, "tDIS", "deploy"), logs, 1, false);
        vm.expectRevert(abi.encodeWithSelector(DeploymentNotFound.selector, "tDIS"));
        harness.cloneStage(at, "tDIS");
    }

    /// @notice An RPC behind the block the deploy landed in refuses before
    /// anything is sent.
    function testCloneWaitsForTheDeployBlock() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("lagging");
        vm.chainId(8453);
        vm.roll(100);
        _deployment(at, 101);
        vm.expectRevert(abi.encodeWithSelector(StageNotReady.selector, 100, 101));
        harness.cloneStage(at, "tDIS");
    }

    function testCloneRefusesWhenItsCloneAlreadyLanded() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("reclone");
        vm.chainId(8453);
        _deployment(at, 1);
        _clone(at, 1);
        vm.expectRevert(abi.encodeWithSelector(StageAlreadyDone.selector, "tDIS", "clone"));
        harness.cloneStage(at, "tDIS");
    }

    function testWireRefusesWithoutPayloads() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("no-payloads");
        vm.removeFile(script.stageFile(at, "tDIS", "payloads"));
        vm.expectRevert(abi.encodeWithSelector(PayloadsMissing.selector, "tDIS"));
        harness.wireStage(at, "tDIS");
    }

    function testWireRefusesWithoutAMinedClone() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("no-clone");
        vm.chainId(8453);
        vm.writeFile(
            script.stageFile(at, "tDIS", "payloads"),
            '{"schemaMeta":"0x00","schemaCid":"","metadataMeta":"0x00","metadataCid":"","mode":"fixed-cids"}'
        );
        _deployment(at, 1);
        vm.expectRevert(abi.encodeWithSelector(NewCloneNotFound.selector, "tDIS"));
        harness.wireStage(at, "tDIS");
    }

    function testHandoffRefusesAnOwnerNotAllowlistedOnBase() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("allowlist");
        vm.writeFile(
            "out/test-launch-unit-allowlist/allowlist.json",
            '[{"address":"0xe70d821f3462a074e63b42d0AaC6523faAe1d611","chainId":1,"roles":["owner"]}]'
        );
        at.allowlist = "out/test-launch-unit-allowlist/allowlist.json";
        TokenPlan memory p = script.plannedToken(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(HandoffTargetNotAllowlisted.selector, SAFE));
        script.checkHandoffTarget(at, p);
    }

    function _prepared(string memory name) internal returns (LaunchBaseTokens.LaunchPaths memory at) {
        at = _paths(name);
        vm.chainId(8453);
        _deployment(at, 1);
        _clone(at, 1);
        vm.writeFile(
            script.stageFile(at, "tDIS", "payloads"),
            '{"schemaMeta":"0x00","schemaCid":"","metadataMeta":"0x00","metadataCid":"","mode":"uploaded"}'
        );
        vm.etch(VAULT, hex"00");
        vm.etch(TEMP, hex"00");
        _mockVault("owner()", abi.encode(SIGNER));
        _mockVault("authorizer()", abi.encode(VAULT));
        _mockVault("name()", abi.encode("The Walt Disney Company ST0x"));
        _mockVault("symbol()", abi.encode("tDIS"));
        vm.mockCall(TEMP, abi.encodeWithSignature("hasRole(bytes32,address)", CERTIFY_ADMIN, SIGNER), abi.encode(true));
    }

    function _payloads(LaunchBaseTokens.LaunchPaths memory at, string memory mode) internal {
        vm.writeFile(
            script.stageFile(at, "tDIS", "payloads"),
            string.concat(
                '{"schemaMeta":"0x00","schemaCid":"","metadataMeta":"0x00","metadataCid":"","mode":"', mode, '"}'
            )
        );
    }

    function _mockVault(string memory signature, bytes memory result) internal {
        vm.mockCall(VAULT, abi.encodeWithSignature(signature), result);
    }

    function _editPlanAddress(LaunchBaseTokens.LaunchPaths memory at, string memory field, address value) internal {
        vm.writeJson(string.concat('"', vm.toString(value), '"'), at.plan, string.concat("$.tokens.tDIS.", field));
    }

    function testWireAndSimulateRefuseAPlanRoutingOwnershipElsewhere() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("foreign-owner");
        address other = address(0xBAD);
        _editPlanAddress(at, "intendedOwner", other);
        vm.expectRevert(abi.encodeWithSelector(HandoffTargetNotAllowlisted.selector, other));
        harness.wireStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(HandoffTargetNotAllowlisted.selector, other));
        harness.simulateStage(at, "tDIS");
    }

    function testWireAndSimulateRefuseEvenAnAllowlistedForeignOwner() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("allowlisted-foreign-owner");
        address other = address(0xBAD);
        _editPlanAddress(at, "intendedOwner", other);
        at.allowlist = string.concat(at.stageDir, "/allowlist.json");
        vm.writeFile(
            at.allowlist, string.concat('[{"address":"', vm.toString(other), '","chainId":8453,"roles":["owner"]}]')
        );
        vm.expectRevert(abi.encodeWithSelector(HandoffTargetNotAllowlisted.selector, other));
        harness.wireStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(HandoffTargetNotAllowlisted.selector, other));
        harness.simulateStage(at, "tDIS");
    }

    function testWireAndSimulateRefuseAPlanRoutingToAnotherAuthoriser() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("foreign-authoriser");
        _editPlanAddress(at, "landingAuthoriser", address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(LandingAuthoriserNotAllowed.selector, address(0xBAD)));
        harness.wireStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(LandingAuthoriserNotAllowed.selector, address(0xBAD)));
        harness.simulateStage(at, "tDIS");
    }

    function _refuseMismatchedVault(LaunchBaseTokens.LaunchPaths memory at) internal {
        vm.removeFile(script.stageFile(at, "tDIS", "clone"));
        vm.expectRevert(abi.encodeWithSelector(VaultMismatch.selector, VAULT));
        harness.cloneStage(at, "tDIS");
        _clone(at, 1);
        vm.expectRevert(abi.encodeWithSelector(VaultMismatch.selector, VAULT));
        harness.wireStage(at, "tDIS");
    }

    function testCloneAndWireRefuseAVaultOwnedBySomeoneElse() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("vault-owner");
        _mockVault("owner()", abi.encode(SAFE));
        _refuseMismatchedVault(at);
    }

    function testCloneAndWireRefuseAVaultWithAnotherName() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("vault-name");
        _mockVault("name()", abi.encode("other"));
        _refuseMismatchedVault(at);
    }

    function testCloneAndWireRefuseAVaultWithAnotherSymbol() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("vault-symbol");
        _mockVault("symbol()", abi.encode("tOTHER"));
        _refuseMismatchedVault(at);
    }

    function testCloneAndWireRefuseAVaultWithNoCode() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("vault-no-code");
        vm.etch(VAULT, hex"");
        _refuseMismatchedVault(at);
    }

    function testWireRefusesAnAlreadyWiredVault() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("already-wired");
        _mockVault("authorizer()", abi.encode(SHARED));
        vm.expectRevert(abi.encodeWithSelector(StageAlreadyDone.selector, "tDIS", "wire"));
        harness.wireStage(at, "tDIS");
    }

    function testWireWaitsForTheCloneBlock() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("clone-block");
        _clone(at, 101);
        vm.roll(100);
        vm.expectRevert(abi.encodeWithSelector(StageNotReady.selector, 100, 101));
        harness.wireStage(at, "tDIS");
    }

    function testWireRefusesATempNotAdministeredByTheSigner() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("temp-admin");
        vm.mockCall(TEMP, abi.encodeWithSignature("hasRole(bytes32,address)", CERTIFY_ADMIN, SIGNER), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(TempAuthoriserNotSigners.selector, TEMP));
        harness.wireStage(at, "tDIS");
    }

    function testWireRefusesFixedCidsUnlessAllowed() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("fixed-cids");
        vm.writeJson('"fixed-cids"', script.stageFile(at, "tDIS", "payloads"), ".mode");
        vm.setEnv("LAUNCH_ALLOW_FIXED_CIDS", "false");
        vm.expectRevert(abi.encodeWithSelector(FixedCidsNotAllowed.selector, "tDIS"));
        harness.wireStage(at, "tDIS");
    }

    function testCheckRefusesExpiredCertification() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("check-expired");
        _mockVault("owner()", abi.encode(SAFE));
        _mockVault("authorizer()", abi.encode(SHARED));
        _mockVault("isCertificationExpired()", abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(LaunchCheckFailed.selector, "tDIS: certification is expired; "));
        script.checkStage(at);
    }

    function testLaunchedAssertionsRefuseExpiredCertification() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("assert-expired");
        _mockVault("owner()", abi.encode(SAFE));
        _mockVault("authorizer()", abi.encode(SHARED));
        _mockVault("isCertificationExpired()", abi.encode(true));
        TokenPlan memory p = script.plannedToken(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, VAULT));
        harness.exposedAssertLaunched(p, VAULT, TEMP);
    }

    function testLaunchedAssertionsRefuseAMissingCertifyGrant() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("assert-certify");
        _mockVault("owner()", abi.encode(SAFE));
        _mockVault("authorizer()", abi.encode(SHARED));
        _mockVault("isCertificationExpired()", abi.encode(false));
        vm.mockCall(TEMP, abi.encodeWithSignature("hasRole(bytes32,address)", CERTIFY, SIGNER), abi.encode(false));
        TokenPlan memory p = script.plannedToken(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(CertifyNotGranted.selector, TEMP));
        harness.exposedAssertLaunched(p, VAULT, TEMP);
    }

    function testLaunchedAssertionsRefuseAVaultNotHandedOff() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("assert-owner");
        _mockVault("authorizer()", abi.encode(SHARED));
        _mockVault("isCertificationExpired()", abi.encode(false));
        vm.mockCall(TEMP, abi.encodeWithSignature("hasRole(bytes32,address)", CERTIFY, SIGNER), abi.encode(true));
        TokenPlan memory p = script.plannedToken(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(OwnershipHandoffFailed.selector, VAULT, SAFE, SIGNER));
        harness.exposedAssertLaunched(p, VAULT, TEMP);
    }

    function testLaunchedAssertionsRefuseAVaultStillOnTheTempAuthoriser() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("assert-authoriser");
        _mockVault("owner()", abi.encode(SAFE));
        _mockVault("authorizer()", abi.encode(TEMP));
        _mockVault("isCertificationExpired()", abi.encode(false));
        vm.mockCall(TEMP, abi.encodeWithSignature("hasRole(bytes32,address)", CERTIFY, SIGNER), abi.encode(true));
        TokenPlan memory p = script.plannedToken(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(AuthoriserNotWired.selector, VAULT, SHARED, TEMP));
        harness.exposedAssertLaunched(p, VAULT, TEMP);
    }

    function testCheckSkipsATokenThatNeverDeployed() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("check-undeployed");
        vm.chainId(8453);
        script.checkStage(at);
    }

    /// @notice A vault deployed but not launched is still the signer's, so the
    /// read-back fails on it.
    function testCheckReportsATokenDeployedButNotLaunched() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("check-stopped");
        _mockVault("authorizer()", abi.encode(TEMP));
        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchCheckFailed.selector,
                string.concat("tDIS: vault ", vm.toString(VAULT), " stopped before its landing authoriser was set; ")
            )
        );
        script.checkStage(at);
    }

    function testCheckPassesATokenNeverDeployed() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("check-not-deployed");
        script.checkStage(at);
    }

    function testCheckReportsADeploySentWithoutAReceipt() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("check-pending");
        vm.writeFile(script.stageFile(at, "tDIS", "deploy"), '{"receipts":[],"pending":["0xabc"]}');
        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchCheckFailed.selector, "tDIS: deploy sent with no receipt, reconcile on chain: 0xabc; "
            )
        );
        script.checkStage(at);
    }

    function testCheckReportsWrongOwnerForALandedToken() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("check-landed-owner");
        _mockVault("authorizer()", abi.encode(SHARED));
        _mockVault("isCertificationExpired()", abi.encode(false));
        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchCheckFailed.selector, string.concat("tDIS: owner() is ", vm.toString(SIGNER), "; ")
            )
        );
        script.checkStage(at);
    }

    function testRecordRefusesAChainOtherThanBase() external {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, 1));
        script.record();
    }

    // record

    function testRecordWritesTheSftOpsRowOnceTheLandingAuthoriserIsSet() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-handed-off");
        _deployment(at, 1);
        _wire(at, true, true);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");

        string memory expected = string.concat(
            "[\n  {\n",
            "    \"symbol\": \"tDIS\",\n",
            "    \"name\": \"The Walt Disney Company ST0x\",\n",
            "    \"sft\": \"",
            vm.toString(VAULT),
            "\",\n    \"wrapper\": \"",
            vm.toString(WRAPPER),
            "\",\n    \"authorizer\": \"0x315b16faa6eE413faBCa877d3851B3818369f0cD\",\n",
            "    \"chainId\": 8453,\n",
            "    \"deployedAt\": \"2026-10-15T15:51:07.450Z\",\n",
            "    \"deployedBy\": \"0x21Cc8a5fe957a167cB92F12F4E658d755b00Be53\",\n"
        );
        expected = string.concat(
            expected,
            "    \"intendedOwner\": \"0xe70d821f3462a074e63b42d0AaC6523faAe1d611\",\n",
            "    \"currentOwner\": \"0xe70d821f3462a074e63b42d0AaC6523faAe1d611\",\n",
            "    \"certifyUntil\": \"2027-10-15T00:00:00.000Z\",\n",
            "    \"smokeTested\": null,\n",
            "    \"handedOff\": null\n  }\n]\n"
        );
        assertEq(vm.readFile(at.ledger), expected);
    }

    /// @notice `create-sft` writes the row before the handoff, so a token
    /// whose handoff did not land is recorded with the signer as owner.
    function testRecordKeepsTheSignerAsOwnerWhenTheHandoffDidNotLand() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-signer");
        _deployment(at, 1);
        _wire(at, false, true);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.parseJsonAddress(vm.readFile(at.ledger), "$[0].currentOwner"), SIGNER);
    }

    function testRecordSkipsATokenThatStoppedBeforeItsLandingAuthoriser() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-stopped");
        _deployment(at, 1);
        _wire(at, true, false);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
        assertEq(
            vm.readFile(string.concat(at.stageDir, "/summary.md")),
            string.concat("- tDIS: vault ", vm.toString(VAULT), " stopped before its landing authoriser was set\n")
        );
    }

    function testRecordSkipsATokenNeverDeployed() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-none");
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
        assertEq(vm.readFile(string.concat(at.stageDir, "/summary.md")), "- tDIS: not deployed\n");
    }

    function testSetAuthorizerToTheTempIsNotLanded() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-temp");
        _deployment(at, 1);
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _log(VAULT, LibLaunchStages.AUTHORIZER_SET_TOPIC, abi.encode(SIGNER, TEMP));
        LibTestLaunchStages.write(script.stageFile(at, "tDIS", "wire"), logs, 1, true);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
        assertEq(
            vm.readFile(string.concat(at.stageDir, "/summary.md")),
            string.concat("- tDIS: vault ", vm.toString(VAULT), " stopped before its landing authoriser was set\n")
        );
    }

    function testRecordToleratesAFailedDeployWithNoPendingKey() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-failed-no-pending");
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _log(
            LibProdDeployV1.STOX_UNIFIED_DEPLOYER, LibLaunchStages.DEPLOYMENT_TOPIC, abi.encode(SIGNER, VAULT, WRAPPER)
        );
        LibTestLaunchStages.write(script.stageFile(at, "tDIS", "deploy"), logs, 1, false);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
        assertEq(vm.readFile(string.concat(at.stageDir, "/summary.md")), "- tDIS: not deployed\n");
    }

    // Ledger layout

    /// @notice A row appended to the committed ledger's layout reproduces the
    /// committed tDIS row byte for byte.
    function testLedgerFormatMatchesTheCommittedLedger() external {
        LedgerRow memory row = LedgerRow({
            symbol: "tDIS",
            name: "The Walt Disney Company ST0x",
            sft: 0x40584fBad768FF46f299Cf50cAe5b3D437E213Fa,
            wrapper: 0x8EA3c97D23872eC4FAe1cA3189039056b77bc703,
            authorizer: SHARED,
            chainId: 8453,
            deployedAt: "2026-10-15T15:51:07.450Z",
            deployedBy: SIGNER,
            intendedOwner: SAFE,
            currentOwner: SAFE,
            certifyUntil: "2027-10-15T00:00:00.000Z"
        });
        assertTrue(_contains(vm.readFile("launch/launches.json"), LibLedger.format(row)));

        string memory path = "out/test-launch-unit-ledger-copy.json";
        vm.writeFile(path, '[\n  {\n    "symbol": "tX"\n  }\n]\n');
        LedgerRow[] memory rows = new LedgerRow[](1);
        rows[0] = row;
        LibLedger.append(path, rows);
        assertEq(vm.readFile(path), string.concat('[\n  {\n    "symbol": "tX"\n  },\n', LibLedger.format(row), "\n]\n"));
    }

    function testLedgerQuoteEscapesLikeJsonStringify() external pure {
        assertEq(LibLedger.quote(unicode"Moët \"A\" \\ B"), unicode"\"Moët \\\"A\\\" \\\\ B\"");
        assertEq(LibLedger.quote("a\nb\tc\x01"), "\"a\\nb\\tc\\u0001\"");
        assertEq(LibLedger.quote("a\rb\x08c\x0c"), "\"a\\rb\\bc\\f\"");
    }

    function testLedgerRefusesAFileThatIsNotAnArray() external {
        string memory path = "out/test-launch-unit-invalid-ledger.json";
        LedgerRow[] memory rows = new LedgerRow[](1);
        string[5] memory notArrays = ["{}", '{"rows":[]}', "[]x", "", "x[]"];
        for (uint256 i = 0; i < notArrays.length; i++) {
            vm.writeFile(path, notArrays[i]);
            vm.expectRevert(abi.encodeWithSelector(LedgerNotAnArray.selector, path));
            harness.exposedAppendLedger(path, rows);
        }
    }

    function testLedgerAppendsSeveralRowsToAnEmptyArray() external {
        string memory path = "out/test-launch-unit-ledger-two-rows.json";
        LedgerRow[] memory rows = new LedgerRow[](2);
        rows[0].symbol = "tA";
        rows[1].symbol = "tB";
        string memory expected =
            string.concat("[\n", LibLedger.format(rows[0]), ",\n", LibLedger.format(rows[1]), "\n]\n");
        vm.writeFile(path, "[]\n");
        harness.exposedAppendLedger(path, rows);
        assertEq(vm.readFile(path), expected);
        vm.writeFile(path, "[ ]\n");
        harness.exposedAppendLedger(path, rows);
        assertEq(vm.readFile(path), expected);
    }

    function testLedgerEscapesEveryHexDigitInLowercase() external pure {
        assertEq(LibLedger.quote("\x1a"), "\"\\u001a\"");
        assertEq(LibLedger.quote("\x0b\x0e\x1d"), "\"\\u000b\\u000e\\u001d\"");
    }

    function testLedgerEscapesHexDigitsInLowercase() external pure {
        assertEq(LibLedger.quote("a\x1bb\x1f"), "\"a\\u001bb\\u001f\"");
    }

    function testLedgerTrimsCarriageReturnsAndTabs() external {
        string memory path = "out/test-launch-unit-ledger-whitespace.json";
        vm.writeFile(path, "[\r\n\t]\r\n");
        LedgerRow[] memory rows = new LedgerRow[](1);
        rows[0].symbol = "tX";
        LibLedger.append(path, rows);
        assertEq(vm.readFile(path), string.concat("[\n", LibLedger.format(rows[0]), "\n]\n"));
    }

    // Stage files

    /// @notice Real forge broadcast files, from `launch/e2e.sh` launching tDIS
    /// on an anvil fork of Base.
    function testReadsForgeBroadcastFiles() external view {
        StageReceipt[] memory deployed = LibLaunchStages.readReceipts("test/fixtures/launch/tDIS-deploy-broadcast.json");
        (bool found, address vault, address wrapper, uint256 blockNumber) =
            LibLaunchStages.findDeployment(deployed, LibProdDeployV1.STOX_UNIFIED_DEPLOYER);
        assertTrue(found);
        assertEq(vault, 0x40584fBad768FF46f299Cf50cAe5b3D437E213Fa);
        assertEq(wrapper, 0x8EA3c97D23872eC4FAe1cA3189039056b77bc703);
        assertEq(blockNumber, 52645051);

        StageReceipt[] memory wired = LibLaunchStages.readReceipts("test/fixtures/launch/tDIS-wire-broadcast.json");
        assertEq(wired.length, 8);
        assertTrue(LibLaunchStages.setAuthorizerLanded(wired, vault, SHARED));
        assertTrue(LibLaunchStages.ownershipTransferred(wired, vault, SAFE));
        assertFalse(LibLaunchStages.ownershipTransferred(wired, vault, SIGNER));
    }

    function testAMissingStageFileHasNoReceipts() external view {
        assertEq(LibLaunchStages.readReceipts("out/test-launch-unit-absent/deploy.json").length, 0);
    }

    function testReadersIgnoreOtherEmitters() external pure {
        Vm.Log[] memory logs = new Vm.Log[](3);
        logs[0] = _log(address(0xBAD), LibLaunchStages.NEW_CLONE_TOPIC, abi.encode(SIGNER, address(1), TEMP));
        logs[1] = _log(address(0xBAD), LibLaunchStages.AUTHORIZER_SET_TOPIC, abi.encode(SIGNER, SHARED));
        logs[2] = _ownershipLog(address(0xBAD));
        StageReceipt[] memory receipts = new StageReceipt[](1);
        receipts[0] = LibLaunchStages.fromRecordedLogs(logs, 1);
        (bool found,,) = LibLaunchStages.findClone(receipts, LibProdLaunchBase.CLONE_FACTORY);
        assertFalse(found);
        assertFalse(LibLaunchStages.setAuthorizerLanded(receipts, VAULT, SHARED));
        assertFalse(LibLaunchStages.ownershipTransferred(receipts, VAULT, SAFE));
    }

    function testReadersIgnoreFailedReceipts() external pure {
        Vm.Log[] memory logs = new Vm.Log[](3);
        logs[0] = _log(
            LibProdLaunchBase.CLONE_FACTORY, LibLaunchStages.NEW_CLONE_TOPIC, abi.encode(SIGNER, address(1), TEMP)
        );
        logs[1] = _log(VAULT, LibLaunchStages.AUTHORIZER_SET_TOPIC, abi.encode(SIGNER, SHARED));
        logs[2] = _ownershipLog(VAULT);
        StageReceipt[] memory receipts = new StageReceipt[](1);
        receipts[0] = LibLaunchStages.fromRecordedLogs(logs, 1);
        receipts[0].success = false;
        (bool found,,) = LibLaunchStages.findClone(receipts, LibProdLaunchBase.CLONE_FACTORY);
        assertFalse(found);
        assertFalse(LibLaunchStages.setAuthorizerLanded(receipts, VAULT, SHARED));
        assertFalse(LibLaunchStages.ownershipTransferred(receipts, VAULT, SAFE));
    }

    function _ownershipLog(address emitter) internal pure returns (Vm.Log memory log) {
        log.emitter = emitter;
        log.topics = new bytes32[](3);
        log.topics[0] = LibLaunchStages.OWNERSHIP_TRANSFERRED_TOPIC;
        log.topics[1] = bytes32(uint256(uint160(SIGNER)));
        log.topics[2] = bytes32(uint256(uint160(SAFE)));
    }

    function testReadersIgnoreOtherEventsFromTheirEmitter() external pure {
        Vm.Log[] memory logs = new Vm.Log[](4);
        bytes32 otherTriple = keccak256("Other(address,address,address)");
        bytes32 otherPair = keccak256("Other(address,address)");
        logs[0] = _log(LibProdDeployV1.STOX_UNIFIED_DEPLOYER, otherTriple, abi.encode(SIGNER, VAULT, WRAPPER));
        logs[1] = _log(LibProdLaunchBase.CLONE_FACTORY, otherTriple, abi.encode(SIGNER, address(1), TEMP));
        logs[2] = _log(VAULT, otherPair, abi.encode(SIGNER, SHARED));
        logs[3] = _ownershipLog(VAULT);
        logs[3].topics[0] = otherPair;
        StageReceipt[] memory receipts = new StageReceipt[](1);
        receipts[0] = LibLaunchStages.fromRecordedLogs(logs, 7);
        (bool deployed,,,) = LibLaunchStages.findDeployment(receipts, LibProdDeployV1.STOX_UNIFIED_DEPLOYER);
        (bool cloned,,) = LibLaunchStages.findClone(receipts, LibProdLaunchBase.CLONE_FACTORY);
        assertFalse(deployed);
        assertFalse(cloned);
        assertFalse(LibLaunchStages.setAuthorizerLanded(receipts, VAULT, SHARED));
        assertFalse(LibLaunchStages.ownershipTransferred(receipts, VAULT, SAFE));
    }

    function testRecordedLogsPreserveEveryField() external pure {
        Vm.Log[] memory logs = new Vm.Log[](3);
        logs[0] = _log(
            LibProdLaunchBase.CLONE_FACTORY, LibLaunchStages.NEW_CLONE_TOPIC, abi.encode(SIGNER, address(1), TEMP)
        );
        logs[1] = _ownershipLog(VAULT);
        logs[2].emitter = address(0xBAD);
        logs[2].topics = new bytes32[](0);
        logs[2].data = hex"010203";
        StageReceipt memory receipt = LibLaunchStages.fromRecordedLogs(logs, 7);
        assertTrue(receipt.success);
        assertEq(receipt.blockNumber, 7);
        assertEq(receipt.logs.length, logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            assertEq(receipt.logs[i].emitter, logs[i].emitter);
            assertEq(receipt.logs[i].topics, logs[i].topics);
            assertEq(receipt.logs[i].data, logs[i].data);
        }
    }

    function testReadsTheFirstCloneLogFromAStageFile() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("first-clone-log");
        _clone(at, 7);
        StageReceipt[] memory receipts = LibLaunchStages.readReceipts(script.stageFile(at, "tDIS", "clone"));
        (bool found, address clone, uint256 clonedAt) =
            LibLaunchStages.findClone(receipts, LibProdLaunchBase.CLONE_FACTORY);
        assertTrue(found);
        assertEq(clone, TEMP);
        assertEq(clonedAt, 7);
    }

    // Role history

    function _role(bytes32 topic, bytes32 role, address account) internal pure returns (Vm.EthGetLogs memory log) {
        log.topics = new bytes32[](4);
        log.topics[0] = topic;
        log.topics[1] = role;
        log.topics[2] = bytes32(uint256(uint160(account)));
        log.topics[3] = bytes32(uint256(uint160(SIGNER)));
    }

    function testRoleHistoryReplaysGrantsAndRevokesInOrder() external pure {
        bytes32 deposit = keccak256("DEPOSIT");
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](5);
        logs[0] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xA));
        logs[1] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xB));
        logs[2] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, keccak256("WITHDRAW"), address(0xC));
        logs[3] = _role(LibRoleHistory.ROLE_REVOKED_TOPIC, deposit, address(0xA));
        logs[4] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xB));
        address[] memory holders = LibRoleHistory.holders(logs, deposit);
        assertEq(holders.length, 1);
        assertEq(holders[0], address(0xB));
    }

    function testRoleHistoryReplaysInChainOrder() external pure {
        bytes32 deposit = keccak256("DEPOSIT");
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](2);
        logs[0] = _role(LibRoleHistory.ROLE_REVOKED_TOPIC, deposit, address(0xA));
        logs[0].blockNumber = 10;
        logs[0].logIndex = 2;
        logs[1] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xA));
        logs[1].blockNumber = 10;
        logs[1].logIndex = 1;
        assertEq(LibRoleHistory.holders(logs, deposit).length, 0);
    }

    function testRoleHistoryOrdersBlocksBeforeLogIndices() external pure {
        bytes32 deposit = keccak256("DEPOSIT");
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](2);
        logs[0] = _role(LibRoleHistory.ROLE_REVOKED_TOPIC, deposit, address(0xA));
        logs[0].blockNumber = 10;
        logs[0].logIndex = 0;
        logs[1] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xA));
        logs[1].blockNumber = 9;
        logs[1].logIndex = 2;
        assertEq(LibRoleHistory.holders(logs, deposit).length, 0);
    }

    function testExclusivityRefusesAStrayHolderOrAMissingMinter() external pure {
        address minter = address(0xA);
        address[] memory holders = new address[](3);
        holders[0] = minter;
        holders[1] = SAFE;
        holders[2] = address(0xB);
        assertEq(
            LibRoleHistory.exclusivityProblems("DEPOSIT", holders, minter, SAFE, true),
            string.concat("DEPOSIT: unexpected holder ", vm.toString(address(0xB)), "; ")
        );

        address[] memory safeOnly = new address[](1);
        safeOnly[0] = SAFE;
        assertEq(
            LibRoleHistory.exclusivityProblems("WITHDRAW", safeOnly, minter, SAFE, true),
            string.concat("WITHDRAW: minter ", vm.toString(minter), " does not hold it; ")
        );
        assertEq(LibRoleHistory.exclusivityProblems("WITHDRAW", safeOnly, minter, SAFE, false), "");
    }

    function testLandingAuthoriserMustBeWherePlanWouldRouteIt() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("landing");
        TokenPlan memory p = script.plannedToken(at, "tDIS");
        script.checkLandingAuthoriser(at, p);

        p.landingAuthoriser = address(0xBAD);
        vm.expectRevert(abi.encodeWithSelector(LandingAuthoriserNotAllowed.selector, address(0xBAD)));
        script.checkLandingAuthoriser(at, p);

        p.dedicated = true;
        vm.expectRevert(abi.encodeWithSelector(LandingAuthoriserNotAllowed.selector, address(0xBAD)));
        script.checkLandingAuthoriser(at, p);

        p.landingAuthoriser = SHARED;
        vm.expectRevert(abi.encodeWithSelector(LandingAuthoriserNotAllowed.selector, SHARED));
        script.checkLandingAuthoriser(at, p);
    }

    function testRecordReportsADeploySentWithoutAReceipt() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-pending");
        vm.writeFile(script.stageFile(at, "tDIS", "deploy"), '{"receipts":[],"pending":["0xabc"]}');
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
        assertEq(
            vm.readFile(string.concat(at.stageDir, "/summary.md")),
            "- tDIS: deploy sent with no receipt, reconcile on chain: 0xabc\n"
        );
    }

    function testHexQuantityHasNoLeadingZeros() external view {
        assertEq(harness.exposedHexQuantity(0), "0x0");
        assertEq(harness.exposedHexQuantity(10), "0xa");
        assertEq(harness.exposedHexQuantity(0x123456789abcdef0), "0x123456789abcdef0");
        assertEq(harness.exposedHexQuantity(52312052), "0x31e37f4");
        assertEq(harness.exposedHexQuantity(255), "0xff");
        string memory allF = "0x";
        for (uint256 i = 0; i < 64; i++) {
            allF = string.concat(allF, "f");
        }
        assertEq(harness.exposedHexQuantity(type(uint256).max), allF);
    }

    function testHexQuantityRoundTrips(uint256 value) external view {
        string memory quantity = harness.exposedHexQuantity(value);
        assertEq(vm.parseUint(quantity), value);
        if (value != 0) assertTrue(bytes(quantity)[2] != "0");
    }

    function testRecordWaitsForReceiptsAndKeepsMinedProgress() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-rpc-lag");
        _deployment(at, 1);
        _wire(at, true, true);
        vm.etch(VAULT, hex"00");
        _mockVault("authorizer()", abi.encode(TEMP));
        _mockVault("owner()", abi.encode(SIGNER));
        _mockVault("isCertificationExpired()", abi.encode(false));
        vm.roll(0);
        vm.expectRevert(abi.encodeWithSelector(StageNotReady.selector, 0, 1));
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
        assertFalse(vm.exists(string.concat(at.stageDir, "/summary.md")));

        vm.roll(1);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        string memory ledger = vm.readFile(at.ledger);
        assertEq(vm.parseJsonAddress(ledger, "$[0].sft"), VAULT);
        assertEq(vm.parseJsonAddress(ledger, "$[0].authorizer"), SHARED);
        assertEq(vm.parseJsonAddress(ledger, "$[0].currentOwner"), SAFE);
        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchCheckFailed.selector,
                string.concat(
                    "tDIS: owner() is ", vm.toString(SIGNER), "; tDIS: authorizer() is ", vm.toString(TEMP), "; "
                )
            )
        );
        script.checkStage(at);
    }

    function testRecordUsesLiveStateWhenWireReceiptsWereNotSaved() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("record-no-wire-receipts");
        assertFalse(vm.exists(script.stageFile(at, "tDIS", "wire")));
        _mockVault("authorizer()", abi.encode(SHARED));
        _mockVault("owner()", abi.encode(SAFE));
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        string memory ledger = vm.readFile(at.ledger);
        assertEq(vm.parseJsonAddress(ledger, "$[0].sft"), VAULT);
        assertEq(vm.parseJsonAddress(ledger, "$[0].authorizer"), SHARED);
        assertEq(vm.parseJsonAddress(ledger, "$[0].currentOwner"), SAFE);
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        for (uint256 i = 0; i + n.length <= h.length; i++) {
            bool hit = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) return true;
        }
        return false;
    }

    function testPlannedTokenReadsTheDedicatedFieldsBack() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("planned-dedicated");
        TokenPlan memory tokenPlan = script.plannedToken(at, "tDIS");
        assertFalse(tokenPlan.dedicated);
        assertFalse(tokenPlan.dedicatedMinterGrantPending);
        vm.writeJson("true", at.plan, "$.tokens.tDIS.dedicatedMinterGrantPending");
        vm.writeJson("true", at.plan, "$.tokens.tDIS.dedicated");
        vm.writeJson("52312053", at.plan, "$.tokens.tDIS.dedicatedDeployBlock");
        _editPlanAddress(at, "dedicatedMinter", address(0x0958));
        tokenPlan = script.plannedToken(at, "tDIS");
        assertTrue(tokenPlan.dedicated);
        assertTrue(tokenPlan.dedicatedMinterGrantPending);
        assertEq(tokenPlan.dedicatedDeployBlock, 52312053);
        assertEq(tokenPlan.dedicatedMinter, address(0x0958));
    }

    function testCloneAndWireRefuseAChainOtherThanBase() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("clone-wire-chain");
        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, block.chainid));
        harness.cloneStage(at, "tDIS");
        vm.expectRevert(abi.encodeWithSelector(WrongChain.selector, block.chainid));
        harness.wireStage(at, "tDIS");
    }

    function testDeployRefusesASentDeployWithNoReceipt() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("deploy-pending");
        vm.chainId(8453);
        _payloads(at, "uploaded");
        vm.writeFile(script.stageFile(at, "tDIS", "deploy"), '{"receipts":[],"pending":["0xabc"]}');
        vm.expectRevert(abi.encodeWithSelector(StageSentUnconfirmed.selector, "tDIS", "deploy", "0xabc"));
        harness.deployStage(at, "tDIS");
    }

    function testCloneRefusesASentCloneWithNoReceipt() external {
        LaunchBaseTokens.LaunchPaths memory at = _prepared("clone-pending");
        vm.writeFile(script.stageFile(at, "tDIS", "clone"), '{"receipts":[],"pending":["0xdef"]}');
        vm.expectRevert(abi.encodeWithSelector(StageSentUnconfirmed.selector, "tDIS", "clone", "0xdef"));
        harness.cloneStage(at, "tDIS");
    }

    /// @notice `deploy` runs `wire`'s pre-flight, so a plan `wire` would
    /// refuse leaves no vault.
    function testDeployRefusesWhatWireWouldRefuse() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("deploy-preflight");
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSelector(PayloadsMissing.selector, "tDIS"));
        harness.deployStage(at, "tDIS");
        _payloads(at, "fixed-cids");
        vm.setEnv("LAUNCH_ALLOW_FIXED_CIDS", "false");
        vm.expectRevert(abi.encodeWithSelector(FixedCidsNotAllowed.selector, "tDIS"));
        harness.deployStage(at, "tDIS");
        _payloads(at, "uploaded");
        _editPlanAddress(at, "landingAuthoriser", address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(LandingAuthoriserNotAllowed.selector, address(0xBAD)));
        harness.deployStage(at, "tDIS");
    }

    function testStagesNeedTheStageDirectory() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("stage-dir");
        assertEq(script.requireStageDir(at).stageDir, at.stageDir);
        at.stageDir = "";
        vm.expectRevert(StageDirUnset.selector);
        script.requireStageDir(at);
    }

    function testRecordTwiceWritesOneRow() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-twice");
        _deployment(at, 1);
        _wire(at, true, true);
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        string memory once = vm.readFile(at.ledger);
        script.recordStage(at, "2026-10-15T16:00:00.000Z");
        assertEq(vm.readFile(at.ledger), once);
        assertEq(vm.readFile(string.concat(at.stageDir, "/summary.md")), "- tDIS: already recorded\n");
    }

    /// @notice A row takes its time from the wire stage's broadcast, not from
    /// when `record()` runs.
    function testRecordStampsTheRowWithTheWireBroadcastTime() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-wire-time");
        _deployment(at, 1);
        _wire(at, true, true);
        vm.writeJson("1792079467450", script.stageFile(at, "tDIS", "wire"), ".timestamp");
        script.recordStage(at, "2030-01-01T00:00:00.000Z");
        assertEq(vm.parseJsonString(vm.readFile(at.ledger), "$[0].deployedAt"), "2026-10-15T15:51:07.450Z");
    }

    function testRecordWaitsForTheDeployBlockWithoutWireReceipts() external {
        LaunchBaseTokens.LaunchPaths memory at = _paths("record-deploy-lag");
        _deployment(at, 5);
        vm.roll(4);
        vm.expectRevert(abi.encodeWithSelector(StageNotReady.selector, 4, 5));
        script.recordStage(at, "2026-10-15T15:51:07.450Z");
        assertEq(vm.readFile(at.ledger), "[]\n");
    }

    function testSimulatedCloneWithoutNewCloneRefuses() external {
        vm.etch(LibProdLaunchBase.CLONE_FACTORY, hex"00");
        vm.mockCall(LibProdLaunchBase.CLONE_FACTORY, abi.encodeWithSignature("clone(address,bytes)"), abi.encode(TEMP));
        vm.expectRevert(abi.encodeWithSelector(NewCloneNotFound.selector, "tDIS"));
        harness.exposedCloneTempAuthoriser("tDIS");
    }

    function testRoleHistoryComparesLogIndicesOnlyWithinABlock() external pure {
        bytes32 deposit = keccak256("DEPOSIT");
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](2);
        logs[0] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xA));
        logs[0].blockNumber = 9;
        logs[0].logIndex = 2;
        logs[1] = _role(LibRoleHistory.ROLE_REVOKED_TOPIC, deposit, address(0xA));
        logs[1].blockNumber = 10;
        logs[1].logIndex = 0;
        assertEq(LibRoleHistory.holders(logs, deposit).length, 0);

        logs[0].topics[0] = LibRoleHistory.ROLE_REVOKED_TOPIC;
        logs[1].topics[0] = LibRoleHistory.ROLE_GRANTED_TOPIC;
        address[] memory holders = LibRoleHistory.holders(logs, deposit);
        assertEq(holders.length, 1);
        assertEq(holders[0], address(0xA));
    }

    function testRoleHistorySkipsNonRoleEvents() external pure {
        bytes32 deposit = keccak256("DEPOSIT");
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](3);
        logs[0].topics = new bytes32[](1);
        logs[0].topics[0] = keccak256("Initialized(uint64)");
        logs[1] = _role(LibRoleHistory.ROLE_GRANTED_TOPIC, deposit, address(0xA));
        logs[1].blockNumber = 1;
        logs[2].topics = new bytes32[](0);
        logs[2].blockNumber = 2;
        address[] memory holders = LibRoleHistory.holders(logs, deposit);
        assertEq(holders.length, 1);
        assertEq(holders[0], address(0xA));
    }
}
