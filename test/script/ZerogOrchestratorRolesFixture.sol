// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibSafeFork} from "rain-deploy-0.1.41/src/lib/LibSafeFork.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.41/src/lib/LibSafeTx.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.25/src/abstract/OffchainAssetReceiptVault.sol";

import {Digest, IST0xOrchestratorV1, MintAuthV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";
import {LibTestZerogTokenCreation} from "../lib/LibTestZerogTokenCreation.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";
import {ExecuteZerogOrchestratorRolesHarness} from "./ExecuteZerogOrchestratorRolesHarness.sol";
import {ScheduleZerogOrchestratorRolesHarness} from "./ScheduleZerogOrchestratorRolesHarness.sol";

/// @title ZerogOrchestratorRolesFixture
/// @notice Live 0G around the 0G orchestrator roles: forks at the token creation's last bundle, lands the schedule as
/// the signers will (three owners `approveHash`, one executes), executes the batch after the delay from a roleless
/// key, and mints and burns as the issuance service through the orchestrator.
abstract contract ZerogOrchestratorRolesFixture is Test {
    /// @notice The block of the token creation's last bundle and its record.
    uint256 internal constant ZEROG_TOKEN_RECORD_BLOCK = LibTestZerogTokenCreation.LAST_BUNDLE_BLOCK;

    /// @notice A Safe owner.
    address internal constant OWNER_A = 0xAB92b327c97A6E7461cBd76E2a789E5e106FF87e;

    /// @notice A Safe owner.
    address internal constant OWNER_B = 0x5CCd3cE683b66ff271DDB8915fF528b8fcFa23c2;

    /// @notice A Safe owner.
    address internal constant OWNER_C = 0xceC2cb8B8EE4000FFA3F8a7f8E0Fa0A3E3DAb72d;

    /// @notice The rebased units the service mints and burns in the proof.
    uint256 internal constant MINT_AMOUNT = 1e18;

    function zerogSafe() internal pure returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(LibSafeInvariants.ZEROG_CHAIN_ID)));
    }

    function zerogTimelock() internal pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function orchestrator() internal pure returns (IST0xOrchestratorV1) {
        return IST0xOrchestratorV1(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
    }

    /// @notice Live 0G with the line at the token creation.
    function forkZerogAtTheTokenRecord() internal {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, ZEROG_TOKEN_RECORD_BLOCK);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "line at the token creation");
        assertEq(zerogSafe().nonce(), 6, "Safe at nonce 6");
    }

    /// @notice Live 0G one block before the token creation's last bundle, with the line at the backfill.
    function forkZerogBeforeTheTokenRecord() internal {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, ZEROG_TOKEN_RECORD_BLOCK - 1);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, "line at the backfill");
    }

    /// @notice The token creation's last bundle, as Safe nonce 5 executed it: the last rows, then the record.
    function landZerogTokenRecord() internal {
        CreateZerogTokensHarness creation = new CreateZerogTokensHarness("zerog-orchestrator-roles");
        creation.callPreflight();
        LibSafeFork.executeBundle(vm, zerogSafe(), creation.callAuthorBundle());
        creation.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "line at the token creation");
    }

    /// @notice The signers, approving the schedule bundle on chain.
    function signers() internal pure returns (address[] memory owners) {
        owners = new address[](3);
        owners[0] = OWNER_A;
        owners[1] = OWNER_B;
        owners[2] = OWNER_C;
    }

    /// @notice The schedule bundle's MultiSend transaction at the Safe's live nonce, and its hash.
    function scheduleSafeTx() internal returns (SafeTx memory multiSend, bytes32 safeTxHash) {
        ScheduleZerogOrchestratorRolesHarness schedule = new ScheduleZerogOrchestratorRolesHarness("signers");
        schedule.callPreflight();
        multiSend = LibSafeTx.multiSendTx(schedule.callAuthorBundle());
        safeTxHash = LibSafeTx.safeTxHash(zerogSafe(), multiSend, zerogSafe().nonce());
    }

    /// @notice The schedule bundle as the signers will land it: three owners each `approveHash` it on chain, then one
    /// of them executes it with the three pre-approved signatures.
    /// @return safeTxHash The hash the three approved.
    function scheduleAsSigners() internal returns (bytes32 safeTxHash) {
        SafeTx memory multiSend;
        (multiSend, safeTxHash) = scheduleSafeTx();
        landAsSigners(multiSend, safeTxHash);
        new ScheduleZerogOrchestratorRolesHarness("signers-post").callAssertPostState();
    }

    /// @notice `txn` as the signers land a 0G Safe transaction: three owners each `approveHash` its hash on chain,
    /// then one of them executes it with the three pre-approved signatures.
    /// @param txn The Safe transaction.
    /// @param safeTxHash Its hash at the Safe's live nonce.
    function landAsSigners(SafeTx memory txn, bytes32 safeTxHash) internal {
        assertEq(LibSafeTx.safeTxHash(zerogSafe(), txn, zerogSafe().nonce()), safeTxHash, "hash at the live nonce");
        address[] memory owners = signers();
        for (uint256 signerIndex = 0; signerIndex < owners.length; signerIndex++) {
            assertTrue(zerogSafe().isOwner(owners[signerIndex]), "signer is an owner");
            vm.prank(owners[signerIndex]);
            zerogSafe().approveHash(safeTxHash);
        }
        vm.prank(OWNER_C);
        assertTrue(LibSafeFork.exec(zerogSafe(), txn, LibSafeTx.approvedHashSignatures(owners)), "Safe executed");
    }

    /// @notice After the delay, `execute()` from the test's default sender, which holds no role.
    function executeAfterTheDelay() internal {
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        new ExecuteZerogOrchestratorRolesHarness("execute").execute();
    }

    /// @notice The execution's record bundle, from the Safe.
    function landExecutionRecord() internal {
        ExecuteZerogOrchestratorRolesHarness record = new ExecuteZerogOrchestratorRolesHarness("record");
        record.callPreflight();
        LibSafeFork.executeBundle(vm, zerogSafe(), record.callAuthorBundle());
        record.callAssertPostState();
    }

    /// @notice The first 0G production token, a US token on the US authoriser.
    function usVault() internal view returns (address vault) {
        vault = LibTokenInvariants.productionTokensZerog()[0].receiptVault;
        assertEq(
            IAuthorisable(vault).authorizer(),
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID),
            "US authoriser"
        );
    }

    /// @notice As the service signer: certifies `vault`, as it does before it mints on every chain, then mints through
    /// the orchestrator to a recipient that signs its authorisation.
    /// @return recipient The recipient.
    function mintAsTheService(address vault) internal returns (address recipient) {
        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        vm.prank(service);
        OffchainAssetReceiptVault(payable(vault)).certify(block.timestamp + 1 days, false, "");

        uint256 key;
        (recipient, key) = makeAddrAndKey("zerog-mint-recipient");
        bytes32 nonce = keccak256("zerog-orchestrator-roles-mint");
        bytes32 digest = Digest.unwrap(orchestrator().mintAuthDigest(vault, recipient, MINT_AMOUNT, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        vm.prank(service);
        orchestrator()
            .mint(vault, recipient, MINT_AMOUNT, MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)}), "");
    }

    /// @notice The recipient hands the shares back to the service signer, which burns them through the orchestrator.
    function burnAsTheService(address vault, address recipient) internal {
        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        vm.prank(recipient);
        assertTrue(IERC20(vault).transfer(service, MINT_AMOUNT), "returned");
        vm.startPrank(service);
        IERC20(vault).approve(address(orchestrator()), MINT_AMOUNT);
        orchestrator().burn(vault, MINT_AMOUNT, "");
        vm.stopPrank();
    }
}
