// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.22/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";

import {ST0xOrchestrator} from "../src/concrete/ST0xOrchestrator.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {grantEuAuthoriserRolesDeclaration} from "./20261006-grant-eu-authoriser-roles.s.sol";

/// @notice The n+1 revoke executed through the Safe and the Safe still
/// holds `EMERGENCY_ROLE`.
error EmergencyNotRevoked();

/// @notice After the bundle, the Safe does not hold `EMERGENCY_ROLE`.
error EmergencyNotGranted();

/// @notice This script's declaration: the line's record after the EU
/// authoriser's role map.
/// @return The declaration.
function grantOrchestratorEmergencyDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.migrationOnto(
        keccak256("script/20261006-grant-orchestrator-emergency.s.sol"), grantEuAuthoriserRolesDeclaration().id
    );
}

/// @title GrantOrchestratorEmergency
/// @notice Authors the per-chain Safe Tx Builder bundle that grants the
/// chain's token-owner Safe `EMERGENCY_ROLE` on the orchestrator and records
/// it, in one atomic MultiSend:
///
/// 1. `orchestrator.grantRole(EMERGENCY, safe)`, only if the Safe does not
///    hold it yet.
/// 2. `registry.applyMigrationV3(WRITER, NAMESPACE, <this script>, [EU
///    authoriser roles])`, written by the Safe as `LibStoxMigrations.WRITER`'s
///    approved delegate.
///
/// `EMERGENCY_ROLE` is administered by `DEFAULT_ADMIN_ROLE`, which the Safe
/// holds until `20261006-orchestrator-admin-to-timelock`, the next record.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261006-grant-orchestrator-emergency` per chain.
contract GrantOrchestratorEmergency is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return grantOrchestratorEmergencyDeclaration();
    }

    /// @notice The orchestrator instance, typed for its role-id getters.
    ST0xOrchestrator internal constant ORCHESTRATOR =
        ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x orchestrator: grant EMERGENCY_ROLE to the token-owner Safe";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261006-grant-orchestrator-emergency-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe, the timelock and the orchestrator are what this repo
    /// pins, and this is the line's next record, which the Safe may write.
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(LibTimelockInvariants.timelockForChainId(block.chainid), chainSafe);
        LibOrchestratorInvariants.assertBeaconSet();
        LibStoxMigrations.assertNext(grantOrchestratorEmergencyDeclaration(), chainSafe);
        LibOrchestratorInvariants.assertInstance();
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The grant if the Safe lacks the role, then the record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address chainSafe = address(safe());
        SafeTx memory record = LibStoxMigrations.recordTx(grantOrchestratorEmergencyDeclaration());
        if (ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), chainSafe)) {
            SafeTx[] memory recordOnly = new SafeTx[](1);
            recordOnly[0] = record;
            return recordOnly;
        }
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: address(ORCHESTRATOR),
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR.EMERGENCY_ROLE(), chainSafe)),
            operation: Enum.Operation.Call
        });
        txs[1] = record;
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record is this bundle's, the Safe holds `EMERGENCY_ROLE`, and
    /// the Safe still carries the token-owner policy.
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(grantOrchestratorEmergencyDeclaration());
        if (!ORCHESTRATOR.hasRole(ORCHESTRATOR.EMERGENCY_ROLE(), address(safe()))) {
            revert EmergencyNotGranted();
        }
        LibOrchestratorInvariants.assertInstance();
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The Safe can still revoke the role under the live threshold.
    /// Re-grants so the fork ends in the post-bundle state.
    function assertReversible() internal override {
        Safe chainSafe = safe();
        bytes32 emergencyRole = ORCHESTRATOR.EMERGENCY_ROLE();
        LibSafeFork.simulateNPlus1(
            vm,
            chainSafe,
            address(ORCHESTRATOR),
            abi.encodeCall(IAccessControl.revokeRole, (emergencyRole, address(chainSafe)))
        );
        if (ORCHESTRATOR.hasRole(emergencyRole, address(chainSafe))) {
            revert EmergencyNotRevoked();
        }
        LibSafeFork.simulateCall(
            vm,
            chainSafe,
            address(ORCHESTRATOR),
            abi.encodeCall(IAccessControl.grantRole, (emergencyRole, address(chainSafe)))
        );
    }
}
