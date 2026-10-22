// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

// forge test compiles only what a test imports, and discovery reads build
// artifacts, so every script and fixture is imported here. A script missing
// from this file fails BuildMigrationsTest with ScriptNotBuilt.

import {DeployGovernanceTimelock} from "../../script/20260729-deploy-governance-timelock.s.sol";
import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {DeployMissingTokens} from "../../script/20260807-deploy-missing-tokens.s.sol";
import {ExecuteTimelockOperations} from "../../script/20260813-execute-timelock-operations.s.sol";
import {TimelockRehearsalCancel} from "../../script/20260813-timelock-rehearsal-cancel.s.sol";
import {TimelockRehearsalSchedule} from "../../script/20260813-timelock-rehearsal-schedule.s.sol";
import {DeployEuAuthoriser} from "../../script/20261006-deploy-eu-authoriser.s.sol";
import {GrantEuAuthoriserRoles} from "../../script/20261006-grant-eu-authoriser-roles.s.sol";
import {RetireDirectSignerRoles} from "../../script/20260831-retire-direct-signer-roles.s.sol";
import {GrantOrchestratorEmergency} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {OrchestratorAdminToTimelock} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {BackfillHistory} from "../../script/20261017-backfill-history.s.sol";
import {MigrateMultisigThreshold} from "../../script/20260619-migrate-multisig-threshold.s.sol";
import {InvalidDeclarationFixture} from "../fixture/declarations/invalid/InvalidDeclarationFixture.s.sol";
import {UndeclaredScriptFixture} from "../fixture/declarations/undeclared/UndeclaredScriptFixture.s.sol";
import {ManyDeclarationsFixtureA} from "../fixture/declarations/many/ManyDeclarationsFixture.s.sol";
import {ValidDeclarationFixture} from "../fixture/declarations/valid/ValidDeclarationFixture.s.sol";
import {ASafeLineFixture} from "../fixture/declarations/timelock/ASafeLineFixture.s.sol";
import {BTimelockLineFirstFixture} from "../fixture/declarations/timelock/BTimelockLineFirstFixture.s.sol";
import {CTimelockLineSecondFixture} from "../fixture/declarations/timelock/CTimelockLineSecondFixture.s.sol";
