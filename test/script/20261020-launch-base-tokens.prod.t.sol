// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IReceiptVaultV1} from "rain-vats-0.2.5/src/interface/deprecated/IReceiptVaultV1.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {DEPOSIT, WITHDRAW, CERTIFY} from "rain-vats-0.2.5/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    LaunchBaseTokens,
    DedicatedAuthoriserNotExclusive,
    DedicatedAuthoriserNotCreatedAt,
    DedicatedAuthoriserNoCode,
    CertifyNotGranted,
    CertificationExpired,
    LaunchCheckFailed,
    ILaunchedVault
} from "../../script/20261020-launch-base-tokens.s.sol";
import {LibRoleHistory} from "../../script/lib/LibRoleHistory.sol";
import {LibLaunchStages} from "../../script/lib/LibLaunchStages.sol";
import {ISetAuthorizer} from "../../script/lib/LibTokenDeployment.sol";
import {LaunchBaseTokensHarness} from "./LaunchBaseTokensHarness.sol";
import {LibProdLaunchBase} from "../../src/lib/LibProdLaunchBase.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {TokenPlan} from "../../src/lib/LibLaunchPlan.sol";
import {LibTestLaunchChain} from "../lib/LibTestLaunchChain.sol";
import {LibTestLaunchStages} from "../lib/LibTestLaunchStages.sol";

/// @title LaunchBaseTokensProdTest
/// @notice The full launch on a Base fork, replaying two real sft-ops launches
/// from the transaction that deployed each token: tDIS on the shared
/// authoriser, and tMC on its dedicated authoriser with the minter's grants
/// pending. Every stage runs as the launch signer, each reading the previous
/// stage's receipts, and the result must match what sft-ops put on chain and
/// in its ledger. Needs a Base archive RPC.
contract LaunchBaseTokensProdTest is Test {
    struct Replay {
        string name;
        string metadataFile;
        string symbol;
        bytes32 deployTx;
        uint256 plannedAt;
        string deployedAt;
        address vault;
        address wrapper;
        address landing;
        uint256 schemaBlock;
        uint256 metaBlock;
    }

    LaunchBaseTokensHarness internal script;

    function setUp() external {
        script = new LaunchBaseTokensHarness();
        vm.makePersistent(address(script));
    }

    function _dis() internal pure returns (Replay memory) {
        return Replay({
            name: "dis",
            metadataFile: "launch/metadata/dis.json",
            symbol: "tDIS",
            deployTx: 0x469f340b04716c6349a6002105b58037ac0abde86812f9ab43609a9ed5b1ca38,
            plannedAt: 1792079467,
            deployedAt: "2026-10-15T15:51:07.450Z",
            vault: 0x40584fBad768FF46f299Cf50cAe5b3D437E213Fa,
            wrapper: 0x8EA3c97D23872eC4FAe1cA3189039056b77bc703,
            landing: 0x315b16faa6eE413faBCa877d3851B3818369f0cD,
            schemaBlock: 52645054,
            metaBlock: 52645055
        });
    }

    function _mc() internal pure returns (Replay memory) {
        return Replay({
            name: "mc",
            metadataFile: "launch/metadata/mc.json",
            symbol: "tMC",
            deployTx: 0x3cde5994ce4e7951ed8c5251d4044aca75948ee2e80a93704904140e0618a23c,
            plannedAt: 1791449907,
            deployedAt: "2026-10-08T08:58:27.373Z",
            vault: 0x6eC2421d74F2AF61b7EE7bCCAE25A3b6a7961Aa0,
            wrapper: 0x378a04202D25659763A02dA5FE77c0a35e64Ce1D,
            landing: 0xDB9152e46c1D140DB6a6f814461f21c571F3275e,
            schemaBlock: 52330275,
            metaBlock: 52330276
        });
    }

    function testReplayDisOnTheSharedAuthoriser() external {
        _replay(_dis());
    }

    function testReplayMcOnItsDedicatedAuthoriser() external {
        _replay(_mc());
    }

    /// @notice A shared-fleet depositor holding DEPOSIT on the dedicated
    /// authoriser stops the simulation and every broadcasting stage that
    /// would act on it.
    function testDedicatedAuthoriserWithAFleetDepositorRefuses() external {
        Replay memory r = _mc();
        r.name = "mc-refusal";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        _stage(at, r.symbol, "deploy");
        _stage(at, r.symbol, "clone");
        vm.mockCall(
            r.landing,
            abi.encodeWithSelector(
                IAccessControl.hasRole.selector, DEPOSIT, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            ),
            abi.encode(true)
        );
        vm.expectPartialRevert(DedicatedAuthoriserNotExclusive.selector);
        script.simulateStage(at, r.symbol);
        vm.expectPartialRevert(DedicatedAuthoriserNotExclusive.selector);
        script.deployStage(at, r.symbol);
        vm.expectPartialRevert(DedicatedAuthoriserNotExclusive.selector);
        script.wireStage(at, r.symbol);
    }

    /// @notice `hasRole` crediting the minter with a grant the role history
    /// does not hold is refused: the history read is incomplete.
    function testDedicatedAuthoriserHistoryMustAgreeWithHasRole() external {
        Replay memory r = _mc();
        r.name = "mc-disagree";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        TokenPlan memory p = script.plannedToken(at, r.symbol);
        vm.mockCall(
            r.landing,
            abi.encodeWithSelector(IAccessControl.hasRole.selector, DEPOSIT, p.dedicatedMinter),
            abi.encode(true)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DedicatedAuthoriserNotExclusive.selector,
                "DEPOSIT: hasRole() says the minter holds it but history disagrees; "
            )
        );
        script.checkDedicatedAuthoriser(p);
    }

    function testDedicatedAuthoriserNotCreatedAtThePinnedBlockRefuses() external {
        Replay memory r = _mc();
        r.name = "mc-creation-block";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        TokenPlan memory p = script.plannedToken(at, r.symbol);
        p.dedicatedDeployBlock++;
        vm.expectRevert(
            abi.encodeWithSelector(DedicatedAuthoriserNotCreatedAt.selector, r.landing, p.dedicatedDeployBlock)
        );
        script.checkDedicatedAuthoriser(p);
        p.dedicatedDeployBlock = 0;
        vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserNotCreatedAt.selector, r.landing, 0));
        script.checkDedicatedAuthoriser(p);
    }

    function testDedicatedAuthoriserWithoutCodeRefuses() external {
        Replay memory r = _mc();
        r.name = "mc-no-code";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        TokenPlan memory p = script.plannedToken(at, r.symbol);
        vm.etch(r.landing, "");
        vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserNoCode.selector, r.landing));
        script.checkDedicatedAuthoriser(p);
    }

    function testDedicatedAuthoriserRefusesAMinterWithoutItsGrants() external {
        Replay memory r = _mc();
        r.name = "mc-minter-required";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        TokenPlan memory p = script.plannedToken(at, r.symbol);
        p.dedicatedMinterGrantPending = false;
        vm.expectRevert(
            abi.encodeWithSelector(
                DedicatedAuthoriserNotExclusive.selector,
                string.concat(
                    "DEPOSIT: minter ",
                    vm.toString(p.dedicatedMinter),
                    " does not hold it; WITHDRAW: minter ",
                    vm.toString(p.dedicatedMinter),
                    " does not hold it; "
                )
            )
        );
        script.checkDedicatedAuthoriser(p);
        vm.rollFork(52334033);
        assertTrue(IAccessControl(r.landing).hasRole(DEPOSIT, p.dedicatedMinter));
        assertTrue(IAccessControl(r.landing).hasRole(WITHDRAW, p.dedicatedMinter));
        script.checkDedicatedAuthoriser(p);
    }

    function testHistoryHolderThatHasRoleDeniesRefuses() external {
        Replay memory r = _mc();
        r.name = "mc-history-holder";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        TokenPlan memory p = script.plannedToken(at, r.symbol);
        // The EU minter's production grant lands after the tMC launch.
        vm.rollFork(52334033);
        address[] memory holders =
            LibRoleHistory.holders(LibRoleHistory.readLogs(r.landing, p.dedicatedDeployBlock, block.number), DEPOSIT);
        assertEq(holders.length, 1);
        assertEq(holders[0], p.dedicatedMinter);
        assertTrue(IAccessControl(r.landing).hasRole(DEPOSIT, holders[0]));
        script.checkDedicatedAuthoriser(p);
        vm.mockCall(
            r.landing, abi.encodeWithSelector(IAccessControl.hasRole.selector, DEPOSIT, holders[0]), abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DedicatedAuthoriserNotExclusive.selector,
                string.concat("DEPOSIT: history says ", vm.toString(holders[0]), " holds it but hasRole() disagrees; ")
            )
        );
        script.checkDedicatedAuthoriser(p);
    }

    function testCheckRefusesAnExpiredCertification() external {
        Replay memory r = _dis();
        r.name = "dis-expired-check";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        _stage(at, r.symbol, "deploy");
        _stage(at, r.symbol, "clone");
        _stage(at, r.symbol, "wire");
        TokenPlan memory p = script.plannedToken(at, r.symbol);
        vm.warp(p.certifyUntil + 1);
        vm.expectRevert(
            abi.encodeWithSelector(LaunchCheckFailed.selector, string.concat(r.symbol, ": certification is expired; "))
        );
        script.checkStage(at);
    }

    function testWireRefusesAnExpiredCertification() external {
        Replay memory r = _dis();
        r.name = "dis-expired-wire";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        _stage(at, r.symbol, "deploy");
        _stage(at, r.symbol, "clone");
        vm.mockCall(r.vault, abi.encodeWithSelector(ILaunchedVault.isCertificationExpired.selector), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, r.vault));
        script.wireStage(at, r.symbol);
    }

    function testWireRefusesMissingCertifyGrant() external {
        Replay memory r = _dis();
        r.name = "dis-missing-certify";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        _stage(at, r.symbol, "deploy");
        _stage(at, r.symbol, "clone");
        (bool cloned, address temp,) = LibLaunchStages.findClone(
            LibLaunchStages.readReceipts(script.stageFile(at, r.symbol, "clone")), LibProdLaunchBase.CLONE_FACTORY
        );
        assertTrue(cloned);
        vm.mockCall(
            temp,
            abi.encodeWithSelector(IAccessControl.hasRole.selector, CERTIFY, LibProdLaunchBase.LAUNCH_SIGNER),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(CertifyNotGranted.selector, temp));
        script.wireStage(at, r.symbol);
    }

    /// @notice The simulation's post-state check is what makes a passing
    /// `simulate` mean anything.
    function testSimulateRefusesAnExpiredCertification() external {
        Replay memory r = _dis();
        r.name = "dis-expired-simulate";
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        vm.writeJson("1", at.plan, "$.tokens.tDIS.certifyUntil");
        vm.expectRevert(abi.encodeWithSelector(CertificationExpired.selector, r.vault));
        script.simulateStage(at, r.symbol);
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

    function _prepare(Replay memory r) internal returns (LaunchBaseTokens.LaunchPaths memory at) {
        vm.createSelectFork(LibRainDeploy.BASE, r.deployTx);
        bytes memory schemaDocument = LibTestLaunchChain.schemaDocument(r.vault, r.schemaBlock);
        bytes memory metaDocument = LibTestLaunchChain.metaDocument(r.vault, r.metaBlock);

        string memory dir = string.concat("out/test-launch-replay-", r.name);
        if (vm.exists(dir)) vm.removeDir(dir, true);
        vm.createDir(dir, true);
        at = LaunchBaseTokens.LaunchPaths({
            plan: string.concat(dir, "/plan.json"),
            stageDir: string.concat(dir, "/stages"),
            ledger: string.concat(dir, "/launches.json"),
            allowlist: "launch/allowlist.json"
        });
        vm.writeFile(at.ledger, "[]\n");
        _writePlan(at, r.metadataFile, r.plannedAt);
        // The documents `prepare` builds; `launch/e2e.sh` runs `prepare` itself
        // through ffi, and the helper's node tests match these bytes.
        vm.createDir(string.concat(at.stageDir, "/", r.symbol), true);
        vm.writeFile(
            script.stageFile(at, r.symbol, "payloads"),
            string.concat(
                "{\"schemaMeta\":\"",
                vm.toString(schemaDocument),
                "\",\"schemaCid\":\"",
                LibTestLaunchChain.cidOf(schemaDocument),
                "\",\"metadataMeta\":\"",
                vm.toString(metaDocument),
                "\",\"metadataCid\":\"",
                LibTestLaunchChain.cidOf(metaDocument),
                "\",\"mode\":\"uploaded\"}"
            )
        );
    }

    function _stage(LaunchBaseTokens.LaunchPaths memory at, string memory symbol, string memory stage)
        internal
        returns (Vm.Log[] memory logs)
    {
        vm.recordLogs();
        if (keccak256(bytes(stage)) == keccak256("deploy")) script.deployStage(at, symbol);
        else if (keccak256(bytes(stage)) == keccak256("clone")) script.cloneStage(at, symbol);
        else script.wireStage(at, symbol);
        logs = vm.getRecordedLogs();
        LibTestLaunchStages.write(script.stageFile(at, symbol, stage), logs, block.number, true);
    }

    function _replay(Replay memory r) internal {
        LaunchBaseTokens.LaunchPaths memory at = _prepare(r);
        // The workflow simulates in its own invocation; here the simulation's
        // deployments are rolled back so the stages see the real nonces.
        uint256 beforeSimulation = vm.snapshotState();
        script.simulateStage(at, r.symbol);
        vm.revertToState(beforeSimulation);

        _stage(at, r.symbol, "deploy");
        _stage(at, r.symbol, "clone");
        Vm.Log[] memory wired = _stage(at, r.symbol, "wire");

        // The same CREATE nonces as the real launch give the same addresses.
        (bool landed,,) = script.recordedRow(at, script.plannedToken(at, r.symbol), "");
        assertTrue(landed);
        assertEq(Ownable(r.vault).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        assertEq(ISetAuthorizer(r.vault).authorizer(), r.landing);
        assertFalse(ILaunchedVault(r.vault).isCertificationExpired());
        _assertPublishedDocuments(wired, r);
        _assertCertification(wired, r.vault, script.plannedToken(at, r.symbol).certifyUntil);

        script.recordStage(at, r.deployedAt);
        string memory ledger = vm.readFile(at.ledger);
        string memory row = _between(ledger, "[\n", "\n]\n");
        assertTrue(_contains(vm.readFile("launch/launches.json"), row), "the appended row is the sft-ops row");
        assertTrue(_contains(row, string.concat("\"sft\": \"", vm.toString(r.vault), "\"")));
        assertTrue(_contains(row, string.concat("\"wrapper\": \"", vm.toString(r.wrapper), "\"")));

        script.checkStage(at);

        // The Safe can act as the owner it was handed.
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        Ownable(r.vault).transferOwnership(address(0xBEEF));
        assertEq(Ownable(r.vault).owner(), address(0xBEEF));
    }

    /// @notice The wiring stage published exactly the documents sft-ops did.
    function _assertPublishedDocuments(Vm.Log[] memory logs, Replay memory r) internal view {
        bytes memory schema = LibTestLaunchChain.schemaDocument(r.vault, r.schemaBlock);
        bytes memory meta = LibTestLaunchChain.metaDocument(r.vault, r.metaBlock);
        uint256 vaultMetas = 0;
        uint256 wrapperMetas = 0;
        bool schemaSeen = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == LibTestLaunchChain.META_V1_2) {
                (, bytes32 subject, bytes memory published) = abi.decode(logs[i].data, (address, bytes32, bytes));
                assertTrue(
                    subject == bytes32(uint256(uint160(r.vault))) || subject == bytes32(uint256(uint160(r.wrapper)))
                );
                assertEq(published, meta);
                if (subject == bytes32(uint256(uint160(r.vault)))) vaultMetas++;
                else wrapperMetas++;
            } else if (logs[i].topics[0] == IReceiptVaultV1.ReceiptVaultInformation.selector) {
                (, bytes memory published) = abi.decode(logs[i].data, (address, bytes));
                assertEq(published, schema);
                schemaSeen = true;
            }
        }
        assertEq(vaultMetas, 1);
        assertEq(wrapperMetas, 1);
        assertTrue(schemaSeen);
    }

    function _assertCertification(Vm.Log[] memory logs, address vault, uint256 plannedUntil) internal pure {
        uint256 certifications = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == vault && logs[i].topics[0] == keccak256("Certify(address,uint256,bool,bytes)")) {
                (address sender, uint256 until, bool forceUntil, bytes memory data) =
                    abi.decode(logs[i].data, (address, uint256, bool, bytes));
                assertEq(sender, LibProdLaunchBase.LAUNCH_SIGNER);
                assertEq(until, plannedUntil);
                assertFalse(forceUntil);
                assertEq(data.length, 0);
                certifications++;
            }
        }
        assertEq(certifications, 1);
    }

    function _between(string memory s, string memory open, string memory close) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 start = bytes(open).length;
        uint256 end = b.length - bytes(close).length;
        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = b[start + i];
        }
        return string(out);
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
}
