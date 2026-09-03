// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {DeployOrchestrator, OrchestratorAlreadyDeployed} from "../../script/20260818-deploy-orchestrator.s.sol";
import {ClosureNotDeployed} from "../../src/lib/LibClosureInvariants.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @notice The orchestrator rollout deadline passed with this chain still
/// pending — the 0.1.30 closure or the instance deploy never landed. Run the
/// outstanding dispatch, extend the deadline, or delete the invariant.
/// @param label The chain still pending.
error OrchestratorRolloutOverdue(string label);

/// @title DeployOrchestratorProdTest
/// @notice PROD coverage for the orchestrator instance deploy: what
/// production IS on each chain, read from a real fork with no mocks. The
/// same test walks the rollout's three states, loudly, so it merges before
/// the broadcasts and keeps asserting after them:
///
/// 1. **Closure pending** (every chain until `manual-sol-artifacts-0-1-30`
///    ships the audited set there): pins the pre-flight refusal — `run()`
///    reverts `ClosureNotDeployed` naming the first missing contract — and
///    logs the outstanding dispatch.
/// 2. **Instance pending** (closure live, no instance): drives
///    `run()` end to end on the fork and asserts the pinned end state — the
///    instance at its nonce-2 pin, `DEFAULT_ADMIN_ROLE` on the chain's
///    token-owner Safe, the vault-logic lock passing, and the proxy's
///    ERC-1967 beacon slot holding the pinned beacon.
/// 3. **Executed** (the broadcast landed): asserts the live instance exactly
///    as state 2 asserted the simulated one — the orchestrator analogue of
///    the token-instance prod asserts — and pins the re-dispatch refusal
///    (`OrchestratorAlreadyDeployed`).
///
/// States 1 and 2 stop passing at `ORCHESTRATOR_ROLLOUT_DEADLINE`: a chain
/// still pending then red-lines cron CI, forcing an explicit operator choice
/// — run the outstanding dispatch, extend the deadline, or delete the
/// invariant. State 3 is the steady state and never expires.
contract DeployOrchestratorProdTest is Test {
    /// @notice Unix timestamp (2026-10-01T00:00:00Z) past which a chain
    /// still in a pending state fails instead of logging PENDING.
    uint256 internal constant ORCHESTRATOR_ROLLOUT_DEADLINE = 1_790_812_800;

    /// @notice The ERC-1967 beacon slot
    /// (`bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)`).
    bytes32 internal constant ERC1967_BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @notice Assert the pinned instance's live wiring: ERC-1967 beacon
    /// slot holding the pinned beacon, the beacon set intact, admin on the
    /// chain's token-owner Safe, and the vault-logic lock passing.
    /// @param label Human chain name, surfaced in assertion messages.
    function assertInstanceLanded(string memory label) internal {
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibOrchestratorInvariants.assertBeaconSet(safe);
        LibOrchestratorInvariants.assertInstance(safe);
        assertEq(
            address(uint160(uint256(vm.load(instance, ERC1967_BEACON_SLOT)))),
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON,
            string.concat(label, ": instance ERC-1967 beacon slot is not the pinned beacon")
        );
    }

    /// @notice Walk the active fork's rollout state (see the contract
    /// NatSpec) and assert it.
    /// @param label Human chain name, surfaced in logs and messages.
    function assertOrchestratorRollout(string memory label) internal {
        DeployOrchestrator script = new DeployOrchestrator();
        address setDeployer = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30;
        address instance = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;

        if (setDeployer.code.length == 0) {
            if (block.timestamp >= ORCHESTRATOR_ROLLOUT_DEADLINE) {
                revert OrchestratorRolloutOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: 0.1.30 closure not deployed"));
            console2.log("-> dispatch manual-sol-artifacts-0-1-30 for every suite, then 20260818-deploy-orchestrator");
            // The pre-flight checks the closure in dependency order, so the
            // corporate-actions facet is the first refusal on a chain with
            // no closure at all.
            vm.expectRevert(
                abi.encodeWithSelector(ClosureNotDeployed.selector, LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30)
            );
            script.run();
            return;
        }

        if (instance.code.length == 0) {
            if (block.timestamp >= ORCHESTRATOR_ROLLOUT_DEADLINE) {
                revert OrchestratorRolloutOverdue(label);
            }
            console2.log(string.concat("PENDING [", label, "]: orchestrator instance not deployed"));
            console2.log("-> dispatch manual-broadcast 20260818-deploy-orchestrator against this chain");
            // Drive the deploy end to end on the fork; `run()`'s own
            // `assertDeployLanded` plus the independent re-assert below pin
            // the end state the real broadcast must reproduce.
            script.run();
            assertInstanceLanded(label);
            return;
        }

        assertInstanceLanded(label);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorAlreadyDeployed.selector, instance));
        script.run();
    }

    function testOrchestratorRolloutBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertOrchestratorRollout("base");
    }

    function testOrchestratorRolloutEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertOrchestratorRollout("ethereum");
    }

    function testOrchestratorRolloutHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertOrchestratorRollout("hyperevm");
    }
}
