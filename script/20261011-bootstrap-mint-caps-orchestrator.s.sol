// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.11/src/lib/LibRainDeploy.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {EvaluableV4} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

import {ST0xOrchestrator, ORCHESTRATOR_MINT_ROLE, ORCHESTRATOR_BURN_ROLE} from "../src/concrete/ST0xOrchestrator.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @notice One account's mint cap: who, and the policy its bucket runs under.
/// @param account The minter or recipient.
/// @param capacity The bucket's burst.
/// @param leakRate The bucket's sustained rate per second.
struct MintCapEntry {
    address account;
    Float capacity;
    Float leakRate;
}

/// @notice What governance seats on the mint-caps orchestrator before
/// minters move over to it.
/// @param weighting The mint weighting expression.
/// @param minters Each is granted `MINT_ROLE` and gets this minter cap.
/// @param recipients Each gets this recipient cap.
/// @param burners Each is granted `BURN_ROLE`.
struct MintCapsBootstrapConfig {
    EvaluableV4 weighting;
    MintCapEntry[] minters;
    MintCapEntry[] recipients;
    address[] burners;
}

/// @notice A contract the bootstrap deploys reached a different address than
/// its pin, so the creation code is not the one the pins were built from.
/// @param expected The pinned address.
/// @param actual The Zoltu address of the creation code.
error BootstrapPinMismatch(address expected, address actual);

/// @notice Neither the Safe nor the timelock holds the authoriser `_ADMIN`
/// role needed to grant the new orchestrator vault access.
/// @param adminRole The missing `_ADMIN` role.
error BootstrapVaultRoleAdminMissing(bytes32 adminRole);

/// @notice The bootstrap operation is already registered on the timelock, so
/// scheduling it again would revert inside the Safe transaction.
/// @param id The operation id.
error BootstrapAlreadyScheduled(bytes32 id);

/// @notice The bootstrap operation is not ready to execute: unknown, already
/// done, or still waiting out its delay.
/// @param id The operation id.
error BootstrapNotExecutable(bytes32 id);

/// @notice The config names no mint weighting interpreter.
error BootstrapWeightingUnset();

/// @notice A post-bootstrap check failed.
/// @param what The property that does not hold.
error BootstrapStateUnexpected(string what);

/// @title BootstrapMintCapsOrchestrator
/// @notice Authors the per-chain Safe bundle that deploys the mint-caps
/// orchestrator next to the live one and schedules its bootstrap on the
/// chain's governance timelock. The live orchestrator
/// (`LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE`) and its beacon
/// are not touched: both instances hold vault access while minters move
/// over.
///
/// The bundle, in order:
///  1. Zoltu-deploys each pin the new orchestrator needs that has no code on
///     the chain: the receipt and receipt-vault implementations and their
///     beacon-set deployer (the orchestrator's vault-logic lock reads its
///     beacons, and `initialize` runs the lock), the orchestrator
///     implementation and its beacon-set deployer. The beacon-set deployer's
///     constructor creates the beacon, owned by the timelock.
///  2. Calls `deploy()` on the beacon-set deployer if the instance has no
///     code. The instance is the deployer's `CREATE` at nonce 2, whoever
///     calls first; `initialize` seats the timelock as every admin.
///  3. Grants the instance `DEPOSIT` and `WITHDRAW` on the chain's
///     authoriser directly, when the Safe holds the `_ADMIN`s.
///  4. Schedules one timelock batch: the authoriser grants (when the
///     timelock holds the `_ADMIN`s), the mint weighting, every minter and
///     recipient cap, and the `MINT_ROLE`/`BURN_ROLE` grants.
///
/// Steps 1-3 are skipped item by item when already done. Execution is
/// permissionless once the delay has run: `execute()` broadcasts it.
///
/// What the bootstrap installs is governance's: a concrete script per
/// deployment supplies `bootstrapConfig()`.
///
/// @dev `run()` simulates the bundle on the fork, warps past the delay,
/// executes the batch from an address holding no roles and asserts the
/// post-bootstrap state and that the live orchestrator's vault access is
/// unchanged, before emitting the artifact.
abstract contract BootstrapMintCapsOrchestrator is Script {
    /// @notice The salt of the bootstrap batch on the timelock.
    bytes32 internal constant BOOTSTRAP_SALT = keccak256("st0x.mint-caps-orchestrator.bootstrap");

    /// @notice Signer-visible `meta.name` for the emitted bundle.
    string internal constant BUNDLE_NAME = "ST0x mint-caps orchestrator: deploy and schedule its bootstrap";

    /// @notice The authoriser roles the orchestrator mints and burns with.
    bytes32 internal constant DEPOSIT = keccak256("DEPOSIT");
    bytes32 internal constant WITHDRAW = keccak256("WITHDRAW");
    bytes32 internal constant DEPOSIT_ADMIN = keccak256("DEPOSIT_ADMIN");
    bytes32 internal constant WITHDRAW_ADMIN = keccak256("WITHDRAW_ADMIN");

    /// @notice What this deployment installs. Governance's; see the contract
    /// NatSpec.
    function bootstrapConfig() internal view virtual returns (MintCapsBootstrapConfig memory);

    /// @notice Chain-suffixed artifact path.
    function artifactPath() internal view virtual returns (string memory) {
        return string.concat("out/20261011-bootstrap-mint-caps-orchestrator-", vm.toString(block.chainid), ".json");
    }

    /// @notice The Zoltu deploys the new orchestrator needs, in dependency
    /// order, each checked against its pin.
    function deployments() internal pure returns (address[] memory pins, bytes[] memory creationCodes) {
        pins = new address[](5);
        creationCodes = new bytes[](5);
        pins[0] = LibProdDeployCurrent.STOX_RECEIPT;
        creationCodes[0] = LibProdDeployV4.STOX_RECEIPT_CREATION_CODE_CANDIDATE;
        pins[1] = LibProdDeployCurrent.STOX_RECEIPT_VAULT;
        creationCodes[1] = LibProdDeployV4.STOX_RECEIPT_VAULT_CREATION_CODE_CANDIDATE;
        pins[2] = LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER;
        creationCodes[2] = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_CANDIDATE;
        pins[3] = LibProdDeployCurrent.ST0X_ORCHESTRATOR;
        creationCodes[3] = LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_CANDIDATE;
        pins[4] = LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER;
        creationCodes[4] = LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_CANDIDATE;
        for (uint256 i = 0; i < pins.length; i++) {
            address actual = LibRainDeploy.zoltuAddress(creationCodes[i]);
            if (actual != pins[i]) revert BootstrapPinMismatch(pins[i], actual);
        }
    }

    /// @notice Whether the timelock grants the authoriser roles, or the Safe
    /// does. Reverts `BootstrapVaultRoleAdminMissing` if neither holds both
    /// `_ADMIN`s.
    function timelockGrantsVaultRoles(address authoriser, address safeAddr, address timelock)
        internal
        view
        returns (bool)
    {
        IAccessControl acl = IAccessControl(authoriser);
        if (acl.hasRole(DEPOSIT_ADMIN, timelock) && acl.hasRole(WITHDRAW_ADMIN, timelock)) return true;
        if (acl.hasRole(DEPOSIT_ADMIN, safeAddr) && acl.hasRole(WITHDRAW_ADMIN, safeAddr)) return false;
        revert BootstrapVaultRoleAdminMissing(acl.hasRole(DEPOSIT_ADMIN, timelock) ? WITHDRAW_ADMIN : DEPOSIT_ADMIN);
    }

    /// @notice The authoriser grants the instance still lacks.
    function vaultGrants(address authoriser, address instance) internal view returns (bytes[] memory grants) {
        IAccessControl acl = IAccessControl(authoriser);
        bool needDeposit = !acl.hasRole(DEPOSIT, instance);
        bool needWithdraw = !acl.hasRole(WITHDRAW, instance);
        grants = new bytes[]((needDeposit ? 1 : 0) + (needWithdraw ? 1 : 0));
        uint256 n = 0;
        if (needDeposit) grants[n++] = abi.encodeCall(IAccessControl.grantRole, (DEPOSIT, instance));
        if (needWithdraw) grants[n++] = abi.encodeCall(IAccessControl.grantRole, (WITHDRAW, instance));
    }

    /// @notice The timelock batch: authoriser grants when the timelock holds
    /// the `_ADMIN`s, then the weighting, the caps and the role grants.
    function bootstrapBatch(
        MintCapsBootstrapConfig memory cfg,
        address authoriser,
        address safeAddr,
        address timelock,
        address instance
    ) internal view returns (address[] memory targets, bytes[] memory payloads) {
        bytes[] memory grants = timelockGrantsVaultRoles(authoriser, safeAddr, timelock)
            ? vaultGrants(authoriser, instance)
            : new bytes[](0);
        uint256 count = grants.length + 1 + cfg.minters.length * 2 + cfg.recipients.length + cfg.burners.length;
        targets = new address[](count);
        payloads = new bytes[](count);
        uint256 n = 0;
        for (uint256 i = 0; i < grants.length; i++) {
            targets[n] = authoriser;
            payloads[n++] = grants[i];
        }
        targets[n] = instance;
        payloads[n++] = abi.encodeCall(ST0xOrchestrator.setMintWeighting, (cfg.weighting));
        for (uint256 i = 0; i < cfg.minters.length; i++) {
            MintCapEntry memory m = cfg.minters[i];
            targets[n] = instance;
            payloads[n++] = abi.encodeCall(ST0xOrchestrator.setMinterMintLimit, (m.account, m.capacity, m.leakRate));
            targets[n] = instance;
            payloads[n++] = abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR_MINT_ROLE, m.account));
        }
        for (uint256 i = 0; i < cfg.recipients.length; i++) {
            MintCapEntry memory r = cfg.recipients[i];
            targets[n] = instance;
            payloads[n++] = abi.encodeCall(ST0xOrchestrator.setRecipientMintLimit, (r.account, r.capacity, r.leakRate));
        }
        for (uint256 i = 0; i < cfg.burners.length; i++) {
            targets[n] = instance;
            payloads[n++] = abi.encodeCall(IAccessControl.grantRole, (ORCHESTRATOR_BURN_ROLE, cfg.burners[i]));
        }
    }

    /// @notice The bootstrap operation's id on `timelock`.
    function bootstrapOperationId(address timelock, address[] memory targets, bytes[] memory payloads)
        internal
        pure
        returns (bytes32)
    {
        return TimelockController(payable(timelock))
            .hashOperationBatch(targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT);
    }

    /// @notice Author the Safe bundle: see the contract-level flow.
    function authorBundle(MintCapsBootstrapConfig memory cfg, address authoriser, address safeAddr, address timelock)
        internal
        view
        returns (SafeTx[] memory txs, bytes32 id)
    {
        if (address(cfg.weighting.interpreter) == address(0)) revert BootstrapWeightingUnset();
        address instance = LibOrchestratorInvariants.mintCapsInstance();

        (address[] memory pins, bytes[] memory creationCodes) = deployments();
        bytes[] memory directGrants = timelockGrantsVaultRoles(authoriser, safeAddr, timelock)
            ? new bytes[](0)
            : vaultGrants(authoriser, instance);
        SafeTx[] memory candidates = new SafeTx[](pins.length + 1 + directGrants.length + 1);
        uint256 n = 0;
        for (uint256 i = 0; i < pins.length; i++) {
            if (pins[i].code.length == 0) {
                candidates[n++] =
                    SafeTx({to: LibRainDeploy.ZOLTU_FACTORY, value: 0, data: creationCodes[i], operation: 0});
            }
        }
        if (instance.code.length == 0) {
            candidates[n++] = SafeTx({
                to: LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER,
                value: 0,
                data: abi.encodeWithSignature("deploy()"),
                operation: 0
            });
        }
        for (uint256 i = 0; i < directGrants.length; i++) {
            candidates[n++] = SafeTx({to: authoriser, value: 0, data: directGrants[i], operation: 0});
        }

        (candidates[n++], id) = scheduleTx(cfg, authoriser, safeAddr, timelock, instance);

        txs = new SafeTx[](n);
        for (uint256 i = 0; i < n; i++) {
            txs[i] = candidates[i];
        }
    }

    /// @notice The Safe transaction scheduling the bootstrap batch on
    /// `timelock` with its minimum delay. Reverts `BootstrapAlreadyScheduled`
    /// if the operation is already registered.
    function scheduleTx(
        MintCapsBootstrapConfig memory cfg,
        address authoriser,
        address safeAddr,
        address timelock,
        address instance
    ) internal view returns (SafeTx memory scheduleCall, bytes32 id) {
        (address[] memory targets, bytes[] memory payloads) =
            bootstrapBatch(cfg, authoriser, safeAddr, timelock, instance);
        id = bootstrapOperationId(timelock, targets, payloads);
        TimelockController tl = TimelockController(payable(timelock));
        if (tl.isOperation(id)) revert BootstrapAlreadyScheduled(id);
        scheduleCall = SafeTx({
            to: timelock,
            value: 0,
            data: abi.encodeCall(
                TimelockController.scheduleBatch,
                (targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT, tl.getMinDelay())
            ),
            operation: 0
        });
    }

    /// @notice Assert the bootstrapped state on the active fork: the
    /// mint-caps beacon set and instance invariants hold, and the instance
    /// carries `cfg` and vault access.
    function assertBootstrapped(MintCapsBootstrapConfig memory cfg, address authoriser, address safeAddr)
        internal
        view
    {
        LibOrchestratorInvariants.assertMintCapsBeaconSet();
        LibOrchestratorInvariants.assertMintCapsInstance(safeAddr);
        ST0xOrchestrator instance = ST0xOrchestrator(payable(LibOrchestratorInvariants.mintCapsInstance()));
        IAccessControl acl = IAccessControl(authoriser);

        _require(
            keccak256(abi.encode(instance.mintWeighting())) == keccak256(abi.encode(cfg.weighting)), "mint weighting"
        );
        for (uint256 i = 0; i < cfg.minters.length; i++) {
            MintCapEntry memory m = cfg.minters[i];
            _require(instance.hasRole(ORCHESTRATOR_MINT_ROLE, m.account), "minter holds MINT_ROLE");
            _require(
                LibDecimalFloat.eq(instance.minterMintLimit(m.account).capacity, m.capacity)
                    && LibDecimalFloat.eq(instance.minterMintLimit(m.account).leakRate, m.leakRate)
                    && instance.minterMintLimit(m.account).set,
                "minter cap"
            );
        }
        for (uint256 i = 0; i < cfg.recipients.length; i++) {
            MintCapEntry memory r = cfg.recipients[i];
            _require(
                LibDecimalFloat.eq(instance.recipientMintLimit(r.account).capacity, r.capacity)
                    && LibDecimalFloat.eq(instance.recipientMintLimit(r.account).leakRate, r.leakRate)
                    && instance.recipientMintLimit(r.account).set,
                "recipient cap"
            );
        }
        for (uint256 i = 0; i < cfg.burners.length; i++) {
            _require(instance.hasRole(ORCHESTRATOR_BURN_ROLE, cfg.burners[i]), "burner holds BURN_ROLE");
        }

        _require(
            acl.hasRole(DEPOSIT, address(instance)) && acl.hasRole(WITHDRAW, address(instance)),
            "new orchestrator holds vault access"
        );
    }

    /// @notice The live orchestrator's vault access, to compare across the
    /// bootstrap: the bundle must leave it as it found it.
    function liveVaultAccess(address authoriser) internal view returns (bool deposit, bool withdraw) {
        address live = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        deposit = IAccessControl(authoriser).hasRole(DEPOSIT, live);
        withdraw = IAccessControl(authoriser).hasRole(WITHDRAW, live);
    }

    function _require(bool ok, string memory what) private pure {
        if (!ok) revert BootstrapStateUnexpected(what);
    }

    /// @notice Simulate the bundle as the Safe, then execute the batch after
    /// the delay from an address holding no roles.
    function simulate(MintCapsBootstrapConfig memory cfg, SafeTx[] memory txs, address authoriser, address safeAddr)
        internal
    {
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        (address[] memory targets, bytes[] memory payloads) =
            bootstrapBatch(cfg, authoriser, safeAddr, timelock, LibOrchestratorInvariants.mintCapsInstance());
        vm.warp(block.timestamp + TimelockController(payable(timelock)).getMinDelay());
        vm.prank(address(uint160(uint256(keccak256("st0x.mint-caps-bootstrap.roleless-executor")))));
        TimelockController(payable(timelock))
            .executeBatch(targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT);
    }

    /// @notice Author the bundle for the active chain, prove it on the fork
    /// and write the Tx Builder artifact. Does not broadcast.
    function run() external {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safeAddr);
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        MintCapsBootstrapConfig memory cfg = bootstrapConfig();

        (SafeTx[] memory txs, bytes32 id) = authorBundle(cfg, authoriser, safeAddr, timelock);
        uint256 nonce = IGnosisSafe(safeAddr).nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(IGnosisSafe(safeAddr), txs, nonce);

        (bool liveDeposit, bool liveWithdraw) = liveVaultAccess(authoriser);
        simulate(cfg, txs, authoriser, safeAddr);
        assertBootstrapped(cfg, authoriser, safeAddr);
        (bool liveDepositAfter, bool liveWithdrawAfter) = liveVaultAccess(authoriser);
        _require(
            liveDeposit == liveDepositAfter && liveWithdraw == liveWithdrawAfter,
            "live orchestrator vault access unchanged"
        );

        string memory json = LibSafeOps.emitTxBuilderJson(safeAddr, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Timelock operation id:", vm.toString(id));
        console2.log("Mint-caps orchestrator:", LibOrchestratorInvariants.mintCapsInstance());
        console2.log("Chain:", block.chainid);
    }

    /// @notice Execute the matured bootstrap batch from the broadcasting key,
    /// which must hold no role: execution is permissionless. The batch is
    /// rebuilt from `bootstrapConfig()` and live state, so it executes only
    /// what this repo commits to.
    function execute() external {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        MintCapsBootstrapConfig memory cfg = bootstrapConfig();
        (address[] memory targets, bytes[] memory payloads) =
            bootstrapBatch(cfg, authoriser, safeAddr, timelock, LibOrchestratorInvariants.mintCapsInstance());
        bytes32 id = bootstrapOperationId(timelock, targets, payloads);
        if (!TimelockController(payable(timelock)).isOperationReady(id)) revert BootstrapNotExecutable(id);

        vm.startBroadcast();
        TimelockController(payable(timelock))
            .executeBatch(targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT);
        vm.stopBroadcast();

        assertBootstrapped(cfg, authoriser, safeAddr);
        console2.log("Executed bootstrap operation:", vm.toString(id));
    }
}
