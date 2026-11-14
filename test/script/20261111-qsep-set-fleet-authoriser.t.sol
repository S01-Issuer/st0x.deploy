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
    RetiredSignerLacksV3Role,
    SafeCannotRevokeV3Role,
    RetiredSignerStillHoldsV3Role,
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
/// @notice The tQSEP `setAuthorizer` and retired-signer revoke Safe bundle on
/// Base before the swap, the refusals of its pre-flight, and the record-only
/// bundle once the swap has executed or off Base.
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

    address internal constant V3 = LibAuthoriserInvariants.STOX_PROD_AUTHORISER_V3_CLONE;

    address internal constant RETIRED = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// The MultiSendCallOnly v1.4.1 the Safe UI executes every multi-call
    /// batch of this Safe through (Safe nonces 698 to 705, for example).
    address internal constant MULTI_SEND_CALL_ONLY = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

    /// The exact bytes of the three revokes, in bundle order.
    bytes internal constant REVOKE_DEPOSIT =
        hex"d547741f87a7811f4bfedea3d341ad165680ae306b01aaeacc205d227629cf157dd9f8210000000000000000000000001c66d6708914c40239d54919320b4c48cae3d1a9";
    bytes internal constant REVOKE_WITHDRAW =
        hex"d547741f7a8dc26796a1e50e6e190b70259f58f6a4edd5b22280ceecc82b687b8e9828690000000000000000000000001c66d6708914c40239d54919320b4c48cae3d1a9";
    bytes internal constant REVOKE_CERTIFY =
        hex"d547741f50a07cb25d0d864370863300b20987dfdae089abad71b607faf639d09d0533910000000000000000000000001c66d6708914c40239d54919320b4c48cae3d1a9";

    function retiredRoles() internal pure returns (bytes32[3] memory) {
        return [keccak256("DEPOSIT"), keccak256("WITHDRAW"), keccak256("CERTIFY")];
    }

    QsepSetFleetAuthoriserHarness internal script;

    function forkPreSwap(string memory stem) internal {
        vm.createSelectFork(LibRainDeploy.BASE, PRE_SWAP_BLOCK);
        script = new QsepSetFleetAuthoriserHarness(stem);
        assertEq(IAuthorisable(VAULT).authorizer(), V3, "pre-swap");
        bytes32[3] memory roles = retiredRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            assertTrue(IAccessControl(V3).hasRole(roles[i], RETIRED), "retired signer holds the role pre-swap");
        }
    }

    function sendAsSafe() internal {
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        (bool ok,) = VAULT.call(SET_AUTHORIZER);
        assertTrue(ok, "the Safe sets the authoriser");
    }

    function revokeAsSafe() internal {
        bytes32[3] memory roles = retiredRoles();
        vm.startPrank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        for (uint256 i = 0; i < roles.length; i++) {
            IAccessControl(V3).revokeRole(roles[i], RETIRED);
        }
        vm.stopPrank();
    }

    /// The MultiSend hash, packed here by hand rather than through
    /// `LibSafeTx`, so the test does not share the script's encoder.
    function multiSendHash(SafeTx[] memory txs, uint256 nonce) internal view returns (bytes32) {
        bytes memory packed = "";
        for (uint256 i = 0; i < txs.length; i++) {
            packed = bytes.concat(packed, bytes1(0x00), bytes20(txs[i].to), bytes32(txs[i].value));
            packed = bytes.concat(packed, bytes32(txs[i].data.length), txs[i].data);
        }
        bytes memory data = abi.encodeWithSignature("multiSend(bytes)", packed);
        return Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE))
            .getTransactionHash(
                MULTI_SEND_CALL_ONLY, 0, data, Enum.Operation.DelegateCall, 0, 0, 0, address(0), address(0), nonce
            );
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

    /// The artifact is four CALLs, value 0, with the exact calldata: the swap
    /// on the vault, then the three revokes on the V3 clone. The returned hash
    /// is the MultiSendCallOnly DELEGATECALL's `safeTxHash` at the Safe's
    /// nonce, which is what the Safe UI shows for a multi-transaction
    /// Transaction Builder batch. The Safe keeps its own V3 roles.
    function testRunAuthorsTheSwapAndTheRevokes() external {
        forkPreSwap("testRunAuthorsTheSwapAndTheRevokes");
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
        assertEq(txs.length, 4, "four transactions");
        bytes[4] memory data = [SET_AUTHORIZER, REVOKE_DEPOSIT, REVOKE_WITHDRAW, REVOKE_CERTIFY];
        for (uint256 i = 0; i < 4; i++) {
            assertEq(txs[i].to, i == 0 ? VAULT : V3, "to");
            assertEq(txs[i].value, 0, "value");
            assertEq(txs[i].data, data[i], "data");
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call), "CALL");
        }
        assertEq(
            vm.parseJsonString(json, ".meta.name"),
            "ST0x tQSEP: setAuthorizer to the fleet authoriser, revoke 0x1c66 V3 roles"
        );
        assertEq(logged, multiSendHash(txs, nonce), "MultiSend hash");
        assertNotEq(logged, directHash(txs[0], nonce), "not the direct CALL hash");

        bytes32[3] memory roles = retiredRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            assertFalse(IAccessControl(V3).hasRole(roles[i], RETIRED), "retired signer revoked");
            assertTrue(IAccessControl(V3).hasRole(roles[i], address(safe)), "Safe keeps its role");
        }
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

        // A revoke of another account than the retired signer.
        tampered =
            vm.replace(json, "1c66d6708914c40239d54919320b4c48cae3d1a9", "3d0cd66efa66c05d86c3d4316b03eae87ab9e8ae");
        LibTestTamperedArtifact.assertVerifyRefusesTamper(vm, address(script), json, tampered, "qsep-revoke-account");

        // A revoke of another role: CERTIFY_ADMIN in place of CERTIFY.
        tampered = vm.replace(
            json,
            "50a07cb25d0d864370863300b20987dfdae089abad71b607faf639d09d053391",
            "48ece560b6811ee496fa3dedc7d5be3dfce8c5eb8f1cc18626507e158a23169b"
        );
        LibTestTamperedArtifact.assertVerifyRefusesTamper(vm, address(script), json, tampered, "qsep-revoke-role");
    }

    /// `verify` refuses an artifact that drops a revoke.
    function testVerifyRefusesAnArtifactWithoutARevoke() external {
        forkPreSwap("testVerifyRefusesAnArtifactWithoutARevoke");
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);
        (uint256 chainId, address artifactSafe, SafeTx[] memory txs) =
            LibSafeTxBuilderJson.fromJson(vm, vm.readFile(script.path()));
        SafeTx[] memory short = new SafeTx[](3);
        for (uint256 i = 0; i < 3; i++) {
            short[i] = txs[i];
        }
        string memory path = "out/qsep-short-8453.json";
        vm.writeFile(path, LibSafeTxBuilderJson.toJson(vm, artifactSafe, chainId, "short", short));
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "txCount"));
        script.verify(path);
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

    /// Each revoke must be live: the pre-flight refuses if the retired signer
    /// no longer holds the role.
    function testRunRefusesARetiredSignerWithoutEachV3Role() external {
        bytes32[3] memory roles = retiredRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            forkPreSwap(string.concat("lacks-", vm.toString(roles[i])));
            vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
            IAccessControl(V3).revokeRole(roles[i], RETIRED);
            vm.expectRevert(abi.encodeWithSelector(RetiredSignerLacksV3Role.selector, roles[i]));
            script.run();
        }
    }

    /// The Safe must hold each role's admin on the V3 clone.
    function testRunRefusesASafeWithoutEachV3RoleAdmin() external {
        bytes32[3] memory roles = retiredRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            forkPreSwap(string.concat("admin-", vm.toString(roles[i])));
            bytes32 admin = IAccessControl(V3).getRoleAdmin(roles[i]);
            vm.mockCall(
                V3,
                abi.encodeCall(IAccessControl.hasRole, (admin, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE)),
                abi.encode(false)
            );
            vm.expectRevert(abi.encodeWithSelector(SafeCannotRevokeV3Role.selector, roles[i]));
            script.run();
            vm.clearMockedCalls();
        }
    }

    /// Once the swap has executed the call is never authored again: the bundle
    /// is the record, which the registry refuses until the line reaches this
    /// script's onto. On Base the line is at genesis before the backfill.
    function testRunRefusesTheSwapOnceExecuted() external {
        forkPreSwap("testRunRefusesTheSwapOnceExecuted");
        sendAsSafe();
        revokeAsSafe();
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMigrationLine.selector, MIGRATION_HEAD_GENESIS));
        script.run();
        assertFalse(vm.exists(script.path()), "a refused run leaves no artifact");
    }

    /// If the swap executed without the revokes, the record is refused: it
    /// attests both.
    function testRunRefusesTheRecordWhileTheRetiredSignerHoldsAV3Role() external {
        forkPreSwap("testRunRefusesTheRecordWhileTheRetiredSignerHoldsAV3Role");
        sendAsSafe();
        vm.expectRevert(abi.encodeWithSelector(RetiredSignerStillHoldsV3Role.selector, keccak256("DEPOSIT")));
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

    /// On Base after the swap and the revokes: the record alone.
    function testRecordOnlyOnBaseAfterTheSwap() external {
        advanceToOnto(LibRainDeploy.BASE);
        revokeAsSafe();
        vm.mockCall(
            VAULT,
            abi.encodeCall(IAuthorisable.authorizer, ()),
            abi.encode(LibAuthoriserInvariants.STOX_PROD_AUTHORISER)
        );
        assertRecordOnly();
    }
}
