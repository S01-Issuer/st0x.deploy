// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {SafeBundleScript} from "rain-deploy-0.1.21/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.21/src/lib/LibSafeTx.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.10/src/lib/LibDecimalFloat.sol";
import {EvaluableV4} from "rainlang-interface-0.2.13/src/interface/IInterpreterCallerV4.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.21/src/interface/IMigrationRegistryV3.sol";

import {ST0xOrchestrator, ORCHESTRATOR_MINT_ROLE, ORCHESTRATOR_BURN_ROLE} from "../src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

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
///     recipient cap, the `MINT_ROLE`/`BURN_ROLE` grants, and the
///     timelock's registry record.
///
/// Steps 1-3 are skipped item by item when already done. Execution is
/// permissionless once the delay has run: `execute()` broadcasts it.
///
/// What the bootstrap installs is governance's `bootstrapConfig()`. Until it
/// is set, the config is empty and `preflight` refuses.
///
/// `run()` and `verify()` are `SafeBundleScript`'s. `assertReversible` proves
/// the scheduled batch on the fork: it warps past the delay, executes the
/// batch from an address holding no roles, asserts the bootstrapped state and
/// that the batch leaves the live orchestrator's vault access unchanged, then
/// returns the fork to the post-bundle state.
contract BootstrapMintCapsOrchestrator is SafeBundleScript {
    /// @notice The salt of the bootstrap batch on the timelock.
    bytes32 internal constant BOOTSTRAP_SALT = keccak256("st0x.mint-caps-orchestrator.bootstrap");

    /// @notice The authoriser roles the orchestrator mints and burns with.
    bytes32 internal constant DEPOSIT = keccak256("DEPOSIT");
    bytes32 internal constant WITHDRAW = keccak256("WITHDRAW");
    bytes32 internal constant DEPOSIT_ADMIN = keccak256("DEPOSIT_ADMIN");
    bytes32 internal constant WITHDRAW_ADMIN = keccak256("WITHDRAW_ADMIN");

    /// @notice What this deployment installs. Governance's; see the contract
    /// NatSpec.
    function bootstrapConfig() internal view virtual returns (MintCapsBootstrapConfig memory cfg) {}

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x mint-caps orchestrator: deploy and schedule its bootstrap";
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Chain-suffixed, for the ACTIVE chain.
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261011-bootstrap-mint-caps-orchestrator-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        if (address(bootstrapConfig().weighting.interpreter) == address(0)) revert BootstrapWeightingUnset();
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
    function timelockGrantsVaultRoles(address authoriser, address safeAddr, address timelockAddr)
        internal
        view
        returns (bool)
    {
        IAccessControl acl = IAccessControl(authoriser);
        if (acl.hasRole(DEPOSIT_ADMIN, timelockAddr) && acl.hasRole(WITHDRAW_ADMIN, timelockAddr)) return true;
        if (acl.hasRole(DEPOSIT_ADMIN, safeAddr) && acl.hasRole(WITHDRAW_ADMIN, safeAddr)) return false;
        revert BootstrapVaultRoleAdminMissing(acl.hasRole(DEPOSIT_ADMIN, timelockAddr) ? WITHDRAW_ADMIN : DEPOSIT_ADMIN);
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
        address timelockAddr,
        address instance
    ) internal view returns (address[] memory targets, bytes[] memory payloads) {
        bytes[] memory grants = timelockGrantsVaultRoles(authoriser, safeAddr, timelockAddr)
            ? vaultGrants(authoriser, instance)
            : new bytes[](0);
        uint256 count = grants.length + 2 + cfg.minters.length * 2 + cfg.recipients.length + cfg.burners.length;
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
        (targets[n], payloads[n]) = LibStoxMigrations.applyMigrationCall(
            timelockAddr,
            LibStoxMigrations.BOOTSTRAP_MINT_CAPS_ORCHESTRATOR,
            LibStoxMigrations.onto(timelockAddr, MIGRATION_HEAD_GENESIS)
        );
    }

    /// @notice The bootstrap batch for the active chain, from
    /// `bootstrapConfig()` and live state.
    function activeBootstrapBatch() internal view returns (address[] memory targets, bytes[] memory payloads) {
        return bootstrapBatch(
            bootstrapConfig(),
            LibAuthoriserInvariants.activeChainAuthoriser(),
            address(safe()),
            timelock(),
            LibOrchestratorInvariants.mintCapsInstance()
        );
    }

    /// @notice The bootstrap operation's id on `timelockAddr`.
    function bootstrapOperationId(address timelockAddr, address[] memory targets, bytes[] memory payloads)
        internal
        pure
        returns (bytes32)
    {
        return TimelockController(payable(timelockAddr))
            .hashOperationBatch(targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT);
    }

    /// @inheritdoc SafeBundleScript
    /// @dev See the contract-level flow.
    function authorBundle() internal view override returns (SafeTx[] memory txs) {
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        address instance = LibOrchestratorInvariants.mintCapsInstance();

        (address[] memory pins, bytes[] memory creationCodes) = deployments();
        bytes[] memory directGrants = timelockGrantsVaultRoles(authoriser, address(safe()), timelock())
            ? new bytes[](0)
            : vaultGrants(authoriser, instance);
        SafeTx[] memory candidates = new SafeTx[](pins.length + 1 + directGrants.length + 1);
        uint256 n = 0;
        for (uint256 i = 0; i < pins.length; i++) {
            if (pins[i].code.length == 0) {
                candidates[n++] = SafeTx({
                    to: LibRainDeploy.ZOLTU_FACTORY, value: 0, data: creationCodes[i], operation: Enum.Operation.Call
                });
            }
        }
        if (instance.code.length == 0) {
            candidates[n++] = SafeTx({
                to: LibProdDeployCurrent.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER,
                value: 0,
                data: abi.encodeWithSignature("deploy()"),
                operation: Enum.Operation.Call
            });
        }
        for (uint256 i = 0; i < directGrants.length; i++) {
            candidates[n++] = SafeTx({to: authoriser, value: 0, data: directGrants[i], operation: Enum.Operation.Call});
        }

        candidates[n++] = scheduleTx();

        txs = new SafeTx[](n);
        for (uint256 i = 0; i < n; i++) {
            txs[i] = candidates[i];
        }
    }

    /// @notice The Safe transaction scheduling the bootstrap batch on the
    /// timelock with its minimum delay. Reverts `BootstrapAlreadyScheduled`
    /// if the operation is already registered.
    function scheduleTx() internal view returns (SafeTx memory) {
        (address[] memory targets, bytes[] memory payloads) = activeBootstrapBatch();
        TimelockController tl = TimelockController(payable(timelock()));
        bytes32 id = bootstrapOperationId(address(tl), targets, payloads);
        if (tl.isOperation(id)) revert BootstrapAlreadyScheduled(id);
        return SafeTx({
            to: address(tl),
            value: 0,
            data: abi.encodeCall(
                TimelockController.scheduleBatch,
                (targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT, tl.getMinDelay())
            ),
            operation: Enum.Operation.Call
        });
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every pin and the instance carry code, the mint-caps beacon set
    /// holds its invariants, the instance has vault access or the batch grants
    /// it, and the batch is pending inside its delay.
    function assertPostState() internal view override {
        (address[] memory pins,) = deployments();
        for (uint256 i = 0; i < pins.length; i++) {
            _require(pins[i].code.length > 0, "pin deployed");
        }
        LibOrchestratorInvariants.assertMintCapsBeaconSet();
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        address instance = LibOrchestratorInvariants.mintCapsInstance();
        if (!timelockGrantsVaultRoles(authoriser, address(safe()), timelock())) {
            _require(vaultGrants(authoriser, instance).length == 0, "new orchestrator holds vault access");
        }
        (address[] memory targets, bytes[] memory payloads) = activeBootstrapBatch();
        TimelockController tl = TimelockController(payable(timelock()));
        bytes32 id = bootstrapOperationId(address(tl), targets, payloads);
        _require(tl.isOperationPending(id) && !tl.isOperationReady(id), "bootstrap pending inside its delay");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Proves the scheduled batch, then returns the fork to the
    /// post-bundle state `run()` writes the artifact from.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        (bool liveDeposit, bool liveWithdraw) = liveVaultAccess(authoriser);
        (address[] memory targets, bytes[] memory payloads) = activeBootstrapBatch();
        TimelockController tl = TimelockController(payable(timelock()));
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + tl.getMinDelay());
        vm.prank(address(uint160(uint256(keccak256("st0x.mint-caps-bootstrap.roleless-executor")))));
        tl.executeBatch(targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT);
        assertBootstrapped(bootstrapConfig(), authoriser, address(safe()));
        (bool liveDepositAfter, bool liveWithdrawAfter) = liveVaultAccess(authoriser);
        _require(
            liveDeposit == liveDepositAfter && liveWithdraw == liveWithdrawAfter,
            "live orchestrator vault access unchanged"
        );
        console2.log("Bootstrap proven: executed after the delay from a roleless address");
        vm.revertToState(postBundle);
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

    /// @notice Execute the matured bootstrap batch from the broadcasting key,
    /// which must hold no role: execution is permissionless. The batch is
    /// rebuilt from `bootstrapConfig()` and live state, so it executes only
    /// what this repo commits to.
    function execute() external {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        (address[] memory targets, bytes[] memory payloads) = activeBootstrapBatch();
        TimelockController tl = TimelockController(payable(timelock()));
        bytes32 id = bootstrapOperationId(address(tl), targets, payloads);
        if (!tl.isOperationReady(id)) revert BootstrapNotExecutable(id);

        vm.startBroadcast();
        tl.executeBatch(targets, new uint256[](targets.length), payloads, bytes32(0), BOOTSTRAP_SALT);
        vm.stopBroadcast();

        assertBootstrapped(bootstrapConfig(), authoriser, safeAddr);
        console2.log("Executed bootstrap operation:", vm.toString(id));
    }
}
