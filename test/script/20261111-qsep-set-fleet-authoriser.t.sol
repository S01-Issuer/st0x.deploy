// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.30/src/interface/IMigrationRegistryV5.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";

import {
    QsepSetFleetAuthoriser,
    QsepUnexpectedAuthoriser,
    QsepVaultNotOwnedBySafe,
    FleetAuthoriserCodehashMismatch,
    OrchestratorLacksFleetRole,
    QsepSetFleetAuthoriserRecorded,
    qsepSetFleetAuthoriserDeclaration
} from "../../script/20261111-qsep-set-fleet-authoriser.s.sol";
import {
    scheduleRevokeServiceSignerDeclaration
} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {
    executeRevokeServiceSignerDeclaration
} from "../../script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol";
import {QsepSetFleetAuthoriserHarness} from "./QsepSetFleetAuthoriserHarness.sol";
import {RevokeServiceSignerDepositWithdrawFixture} from "./RevokeServiceSignerDepositWithdrawFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestTamperedArtifact} from "../lib/LibTestTamperedArtifact.sol";
import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {IOwnable} from "../../src/interface/IOwnable.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title QsepSetFleetAuthoriserTest
/// @notice The tQSEP `setAuthorizer` Safe bundle on Base before the swap, the
/// refusals of its pre-flight, and the record-only bundle once the swap has
/// executed or off Base.
/// @dev The swap tests fork Base at `PRE_SWAP_BLOCK`, where the vault is on
/// the V3 clone and the orchestrator holds DEPOSIT and WITHDRAW on the fleet
/// authoriser, so they do not change once the Safe transaction executes.
contract QsepSetFleetAuthoriserTest is RevokeServiceSignerDepositWithdrawFixture {
    /// The exact bytes the signers import: `setAuthorizer(STOX_PROD_AUTHORISER)`.
    bytes internal constant SET_AUTHORIZER =
        hex"058a628f000000000000000000000000315b16faa6ee413fabca877d3851b3818369f0cd";

    /// Same block as `QsepAuthoriserProdTest.PRE_SWAP_BLOCK`.
    uint256 internal constant PRE_SWAP_BLOCK = 55685398;

    address internal constant VAULT = LibTokenInvariants.QSEP_RECEIPT_VAULT;

    QsepSetFleetAuthoriserHarness internal script;

    function forkPreSwap(string memory stem) internal {
        vm.createSelectFork(LibRainDeploy.BASE, PRE_SWAP_BLOCK);
        script = new QsepSetFleetAuthoriserHarness(stem);
        assertEq(IAuthorisable(VAULT).authorizer(), LibAuthoriserInvariants.STOX_PROD_AUTHORISER_V3_CLONE, "pre-swap");
    }

    function sendAsSafe() internal {
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        (bool ok,) = VAULT.call(SET_AUTHORIZER);
        assertTrue(ok, "the Safe sets the authoriser");
    }

    function directHash(SafeTx memory txn, uint256 nonce) internal view returns (bytes32) {
        return Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE))
            .getTransactionHash(txn.to, txn.value, txn.data, txn.operation, 0, 0, 0, address(0), address(0), nonce);
    }

    function testDeclarationIsTheScriptPathAfterTheRevokeExecution() external pure {
        ScriptDeclaration memory declared = qsepSetFleetAuthoriserDeclaration();
        assertEq(declared.id, keccak256("script/20261111-qsep-set-fleet-authoriser.s.sol"), "id");
        assertEq(declared.onto, LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER, "onto");
        assertFalse(declared.history, "a record");
    }

    /// The artifact is one CALL to the vault, value 0, with the exact
    /// calldata, and the returned hash is that CALL's `safeTxHash` at the
    /// Safe's nonce, which is what the Safe UI shows for a one-transaction
    /// Transaction Builder batch.
    function testRunAuthorsTheOneCallSwap() external {
        forkPreSwap("testRunAuthorsTheOneCallSwap");
        Safe safe = Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
        uint256 nonce = safe.nonce();
        bytes32 logged = script.run();

        assertEq(IAuthorisable(VAULT).authorizer(), LibAuthoriserInvariants.STOX_PROD_AUTHORISER, "swapped");
        assertEq(IOwnable(VAULT).owner(), address(safe), "owner");
        assertEq(safe.nonce(), nonce + 1, "one Safe transaction");

        string memory json = vm.readFile(script.path());
        (uint256 chainId, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, json);
        assertEq(chainId, 8453, "chain");
        assertEq(artifactSafe, address(safe), "Safe");
        assertEq(txs.length, 1, "one transaction");
        assertEq(txs[0].to, VAULT, "to");
        assertEq(txs[0].value, 0, "value");
        assertEq(txs[0].data, SET_AUTHORIZER, "data");
        assertEq(vm.parseJsonString(json, ".meta.name"), "ST0x tQSEP: setAuthorizer to the fleet authoriser");
        assertEq(logged, directHash(txs[0], nonce), "direct CALL hash");
    }

    /// `verify` accepts the artifact `run` wrote, on the state before it, and
    /// refuses one whose calldata names another authoriser.
    function testVerifyAcceptsTheArtifactAndRefusesATamper() external {
        forkPreSwap("testVerifyAcceptsTheArtifactAndRefusesATamper");
        uint256 preRun = vm.snapshotState();
        bytes32 logged = script.run();
        vm.revertToState(preRun);
        assertEq(script.verify(script.path()), logged, "same hash at the same nonce");

        string memory json = vm.readFile(script.path());
        string memory tampered =
            vm.replace(json, "315b16faa6ee413fabca877d3851b3818369f0cd", "35f9fa9d80aaf2b0fb27f0ff015641b3408d7456");
        LibTestTamperedArtifact.assertVerifyRefusesTamper(vm, address(script), json, tampered, "qsep-set-fleet");
    }

    function testRunRefusesAVaultTheSafeDoesNotOwn() external {
        forkPreSwap("testRunRefusesAVaultTheSafeDoesNotOwn");
        vm.mockCall(VAULT, abi.encodeCall(IOwnable.owner, ()), abi.encode(address(0xdead)));
        vm.expectRevert(abi.encodeWithSelector(QsepVaultNotOwnedBySafe.selector, address(0xdead)));
        script.run();
    }

    function testRunRefusesAnUnexpectedAuthoriser() external {
        forkPreSwap("testRunRefusesAnUnexpectedAuthoriser");
        vm.mockCall(VAULT, abi.encodeCall(IAuthorisable.authorizer, ()), abi.encode(address(0xbeef)));
        vm.expectRevert(abi.encodeWithSelector(QsepUnexpectedAuthoriser.selector, address(0xbeef)));
        script.run();
    }

    function testRunRefusesAFleetAuthoriserWithOtherCode() external {
        forkPreSwap("testRunRefusesAFleetAuthoriserWithOtherCode");
        address fleet = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;
        vm.etch(fleet, hex"00");
        vm.expectRevert(abi.encodeWithSelector(FleetAuthoriserCodehashMismatch.selector, keccak256(hex"00")));
        script.run();
    }

    function assertRefusesWithoutRole(bytes32 role) internal {
        forkPreSwap(vm.toString(role));
        vm.mockCall(
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            abi.encodeCall(IAccessControl.hasRole, (role, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR)),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(OrchestratorLacksFleetRole.selector, role));
        script.run();
    }

    function testRunRefusesAnOrchestratorWithoutDeposit() external {
        assertRefusesWithoutRole(keccak256("DEPOSIT"));
    }

    function testRunRefusesAnOrchestratorWithoutWithdraw() external {
        assertRefusesWithoutRole(keccak256("WITHDRAW"));
    }

    /// Once the swap has executed the call is never authored again: the bundle
    /// is the record, which the registry refuses until the line reaches this
    /// script's onto. On Base the line is at genesis before the backfill.
    function testRunRefusesTheSwapOnceExecuted() external {
        forkPreSwap("testRunRefusesTheSwapOnceExecuted");
        sendAsSafe();
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, MIGRATION_HEAD_GENESIS));
        script.run();
        assertFalse(vm.exists(script.path()), "a refused run leaves no artifact");
    }

    /// Brings `network`'s root line to this script's onto.
    function advanceToOnto(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        script = new QsepSetFleetAuthoriserHarness(network);
        advanceRootLineToRevokeSchedule();
        writeRecord(scheduleRevokeServiceSignerDeclaration());
        writeRecord(executeRevokeServiceSignerDeclaration());
        assertEq(LibStoxMigrations.head(), qsepSetFleetAuthoriserDeclaration().onto, "line at the onto");
    }

    function assertRecordOnly() internal {
        bytes32 logged = script.run();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER, "recorded");
        (,, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(script.path()));
        assertEq(txs.length, 1, "record only");
        SafeTx memory record = LibStoxMigrations.recordTx(qsepSetFleetAuthoriserDeclaration());
        assertEq(txs[0].to, record.to, "registry");
        assertEq(txs[0].data, record.data, "record calldata");
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        assertEq(
            logged,
            safe.getTransactionHash(
                record.to, 0, record.data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), safe.nonce() - 1
            ),
            "direct CALL hash"
        );

        vm.expectRevert(
            abi.encodeWithSelector(QsepSetFleetAuthoriserRecorded.selector, LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER)
        );
        script.run();
    }

    /// Off Base there is no tQSEP vault: the bundle is the record alone.
    function testRecordOnlyOffBase() external {
        advanceToOnto(LibStoxDeployNetworks.ETHEREUM);
        assertRecordOnly();
    }

    /// On Base after the swap: the record alone.
    function testRecordOnlyOnBaseAfterTheSwap() external {
        advanceToOnto(LibRainDeploy.BASE);
        vm.mockCall(
            VAULT,
            abi.encodeCall(IAuthorisable.authorizer, ()),
            abi.encode(LibAuthoriserInvariants.STOX_PROD_AUTHORISER)
        );
        assertRecordOnly();
    }
}
