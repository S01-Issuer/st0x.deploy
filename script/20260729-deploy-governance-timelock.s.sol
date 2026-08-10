// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice A chain's hydrated governance-timelock pin does not equal the
/// address its own Safe derives. Either the pin records a different chain's
/// timelock or the Safe behind it has moved — deploying or asserting against
/// it would target the wrong contract.
/// @param chainId The chain whose pin disagrees with the derivation.
/// @param pinned The hydrated pin.
/// @param derived The address derived from that chain's Safe.
error TimelockPinMismatch(uint256 chainId, address pinned, address derived);

/// @notice The canonical Zoltu deterministic-deployment factory is not
/// deployed on this network. Without it the derived address is unreachable.
/// @param factory The pinned factory address with no code.
error ZoltuFactoryNotDeployed(address factory);

/// @notice The Zoltu factory's runtime codehash does not match the
/// rain-deploy pin. The contract at the pinned address is not the canonical
/// factory, so nothing may be deployed through it.
/// @param factory The factory address inspected.
/// @param expected The pinned factory codehash.
/// @param actual The codehash observed on-chain.
error ZoltuFactoryCodehashMismatch(address factory, bytes32 expected, bytes32 actual);

/// @notice The address the Zoltu factory returned does not match the
/// in-source CREATE2 derivation. Either the factory is not the canonical
/// one (should be unreachable behind the codehash pin) or the derivation
/// has drifted from the factory's semantics.
/// @param expected The derived timelock address.
/// @param actual The address the factory deployed to.
error TimelockAddressMismatch(address expected, address actual);

/// @notice The broadcasting deploy key holds a role on the freshly-deployed
/// timelock. The constructor was given `admin = address(0)` precisely so the
/// deployer is never granted anything; a role here means the deploy did not
/// produce the pinned configuration.
/// @param role The role the deployer unexpectedly holds.
/// @param deployer The broadcasting deploy key.
error DeployerHoldsTimelockRole(bytes32 role, address deployer);

/// @title DeployGovernanceTimelock
/// @notice **PENDING.** Broadcast script that deploys the ST0x governance
/// timelock — an unmodified, pre-audited OZ `TimelockController` — on the
/// active chain via the Zoltu deterministic factory, configured entirely by
/// its constructor:
///
///   - `minDelay` = `LibTimelockInvariants.TIMELOCK_MIN_DELAY` (48 hours),
///   - proposers = `[the chain's token-owner Safe]` (which the OZ
///     constructor also makes canceller),
///   - executors = `[the chain's token-owner Safe]`,
///   - `admin` = `address(0)` — the timelock self-administers from birth.
///
/// Because `admin` is zero the CI deploy key is NEVER granted any role on
/// the timelock: there is no configuration window and nothing to revoke —
/// the deploy-then-renounce ceremony the V4 authoriser clone needed
/// collapses into a single constructor-configured deploy. The post-state
/// assertion still proves the deployer holds nothing, closing the gap
/// structurally AND observably.
///
/// Deploying the timelock grants it no power: it becomes the governance
/// admin only when the Safe executes the separate
/// `20260729-migrate-governance-to-timelock` bundle (vault ownership +
/// authoriser `_ADMIN` roles), which is a Safe-signed artifact, not a
/// deploy-key action.
///
/// Dispatched via `.github/workflows/manual-broadcast.yaml` with
/// `script = 20260729-deploy-governance-timelock` and `network = base` /
/// `ethereum`, broadcasting as the CI deploy key (`secrets.PRIVATE_KEY`) —
/// the same key and flow the impl deploys use. The Zoltu deploy is
/// idempotent per network: the address is a pure function of the creation
/// code, and a second dispatch refuses at pre-flight.
///
/// After each chain's broadcast, the post-execution pin PR hydrates that
/// chain's `LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK*` pin with the
/// logged address (`testPinsMatchDerivedAddressesOnceHydrated` pins the
/// hydrated value to the derivation).
contract DeployGovernanceTimelock is Script {
    /// @notice Every chain the governance timelock is deployed to, in a
    /// fixed order. One dispatch covers all of them: the deploy is
    /// deterministic and idempotent per chain, so a chain that already
    /// carries the timelock is verified and skipped rather than redeployed.
    /// @return nets The network names, matching `foundry.toml`'s
    /// `[rpc_endpoints]` aliases.
    function networks() internal pure returns (string[] memory nets) {
        nets = new string[](3);
        nets[0] = LibRainDeploy.BASE;
        nets[1] = LibStoxDeployNetworks.ETHEREUM;
        nets[2] = LibStoxDeployNetworks.HYPEREVM;
    }

    /// @notice Deploy the governance timelock across every chain in
    /// `networks()` in a single dispatch, skipping any chain that already
    /// carries it.
    ///
    /// The address is a pure function of the chain's Safe (the only
    /// constructor input that varies), so each chain has its own derived
    /// address and the deploy is idempotent per chain: an already-deployed
    /// chain is asserted into its pinned configuration and skipped, never
    /// redeployed. That makes a re-dispatch a safe no-op, and lets a partial
    /// rollout (one chain broadcast, another not) finish in a single run
    /// rather than needing a separate dispatch per chain.
    function run() external {
        string[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            // The fork id is unused; bind it so the unused-return lint stays
            // satisfied, matching `LibRainDeploy.deployToNetworks`.
            uint256 forkId = vm.createSelectFork(nets[i]);
            (forkId);
            console2.log("==== NETWORK:", nets[i]);
            _deployOnActiveChain();
        }
    }

    /// @notice Deploy (or verify-and-skip) the timelock on whichever chain is
    /// currently selected. Pre-flight covers everything the deploy relies on:
    /// the chain's Safe carries the pinned policy, any hydrated pin agrees
    /// with the derivation, and the Zoltu factory is canonical. Post-state
    /// proves the landed timelock carries the full pinned configuration and
    /// that the deployer holds nothing.
    function _deployOnActiveChain() internal {
        // Resolve THIS chain's token-owner Safe and assert it is in its
        // expected state — the Safe is baked into the timelock's constructor
        // as sole proposer + executor, so a drifted Safe would bake
        // governance onto a shape we no longer recognise.
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address expected = LibTimelockInvariants.expectedTimelockAddress(safe);

        // A hydrated pin must agree with what this chain's Safe derives.
        // Disagreement means the pin records another chain's timelock, or the
        // Safe behind it moved — either way the wrong contract.
        address pinned = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (pinned != address(0) && pinned != expected) {
            revert TimelockPinMismatch(block.chainid, pinned, expected);
        }

        // Already deployed: assert it is the timelock we expect, then skip.
        // The Zoltu deploy is idempotent, so this keeps a re-dispatch a clean
        // no-op while still proving the live contract's configuration.
        if (expected.code.length != 0) {
            LibTimelockInvariants.assertTimelockState(expected, safe);
            console2.log(" - Timelock already deployed, skipping:", vm.toString(expected));
            if (pinned == address(0)) {
                console2.log(" - PIN OUTSTANDING: hydrate this chain's LibTimelockInvariants pin with the above");
            }
            return;
        }

        // The canonical Zoltu factory is deployed with the pinned codehash. A
        // missing or replaced factory would either revert or deploy through
        // attacker-controlled machinery.
        address factory = LibRainDeploy.ZOLTU_FACTORY;
        if (factory.code.length == 0) revert ZoltuFactoryNotDeployed(factory);
        bytes32 factoryCodehash = factory.codehash;
        if (factoryCodehash != LibRainDeploy.ZOLTU_FACTORY_CODEHASH) {
            revert ZoltuFactoryCodehashMismatch(factory, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, factoryCodehash);
        }

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender resolves
        // to the broadcast address (the CI deploy key in production).
        // Captured for the holds-nothing post-state check.
        address deployer = msg.sender;

        address timelock = LibRainDeploy.deployZoltu(LibTimelockInvariants.timelockInitCode(safe));

        vm.stopBroadcast();

        if (timelock != expected) revert TimelockAddressMismatch(expected, timelock);

        _assertPostState(timelock, safe, deployer);

        // Log the timelock address prominently so the operator can copy it
        // into the post-execution pin PR (hydrate this chain's
        // `LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK*` pin).
        console2.log("==== GOVERNANCE TIMELOCK DEPLOYED ====");
        console2.log("Chain:", block.chainid);
        console2.log("Timelock:", vm.toString(timelock));
        console2.log("Codehash:", vm.toString(timelock.codehash));
        console2.log("MinDelay (seconds):", LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        console2.log("Proposer/Canceller/Executor Safe:", vm.toString(safe));
        console2.log("======================================");
    }

    /// @notice Post-state assertion invoked after the deploy: the timelock
    /// carries the full pinned configuration
    /// (`LibTimelockInvariants.assertTimelockState` — codehash, minDelay,
    /// Safe role set, self-administration, no open roles) and the deployer
    /// holds none of the timelock's roles. Split from `run()` so tests can
    /// call it against a timelock they deployed directly.
    /// @param timelock The freshly-deployed timelock.
    /// @param safe The chain's token-owner Safe.
    /// @param deployer The address that broadcast the deploy.
    function _assertPostState(address timelock, address safe, address deployer) internal view {
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        IAccessControl acl = IAccessControl(timelock);
        bytes32[4] memory roles = [
            LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
            LibTimelockInvariants.TIMELOCK_CANCELLER_ROLE,
            LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE,
            LibTimelockInvariants.TIMELOCK_DEFAULT_ADMIN_ROLE
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            if (acl.hasRole(roles[i], deployer)) {
                revert DeployerHoldsTimelockRole(roles[i], deployer);
            }
        }
    }
}
