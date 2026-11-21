// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.38/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {ICloneableV2} from "rain-factory-0.2.18/src/interface/ICloneableV2.sol";
import {
    OffchainAssetReceiptVault,
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.2.25/src/abstract/OffchainAssetReceiptVault.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.2.25/src/abstract/ReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {IReceiptV3} from "rain-vats-0.2.25/src/interface/IReceiptV3.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.25/src/interface/IReceiptVaultV3.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {IAuthorisable} from "../src/interface/IAuthorisable.sol";
import {IStoxUnifiedDeployerV1} from "../src/interface/IStoxUnifiedDeployerV1.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibClosureInvariants} from "../src/lib/LibClosureInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {RoleGrant} from "../src/lib/RoleGrant.sol";

/// @notice A 0G token table row already has a deployed address, or names another underlying than its config row.
/// @param index The row.
error ZerogTokenRowNotPlaceholder(uint256 index);

/// @notice The 0G token table has another number of rows than the configs, so its rows cannot pair with them by index.
/// @param tableLength The table's row count.
/// @param rowCount The config row count.
error ZerogTokenTableLengthMismatch(uint256 tableLength, uint256 rowCount);

/// @notice A created token is not wired, owned, authorised, named or empty as expected.
/// @param underlying The token's underlying.
/// @param field What does not match.
error ZerogTokenMismatch(string underlying, string field);

/// @notice The 0.1.1 deployers created something other than one receipt, vault and wrapper per token, or more tokens
/// than there are rows, so the created tokens cannot be paired with the rows.
/// @param vaultDeployerNonce The receipt-vault beacon-set deployer's nonce.
/// @param wrapperDeployerNonce The wrapper beacon-set deployer's nonce.
error ZerogDeployersOutOfStep(uint256 vaultDeployerNonce, uint256 wrapperDeployerNonce);

/// @notice After a bundle that does not create the last row, the migration is recorded or the line moved.
/// @param head The line's head.
error ZerogTokensRecordedEarly(bytes32 head);

/// @notice The token-owner Safe still holds an admin role on a 0G authoriser clone it initialised.
/// @param authoriser The clone.
/// @param role The role the Safe holds.
error ZerogAuthoriserSafeAdmin(address authoriser, bytes32 role);

/// @notice A 0G authoriser clone grants a role to the orchestrator's pinned address, which no reviewed step creates on
/// 0G (`LibAuthoriserInvariants.grantsOrchestrator`).
/// @param authoriser The clone.
/// @param role The role it grants.
error ZerogOrchestratorGranted(address authoriser, bytes32 role);

/// @notice This script's declaration on the root line: right after the backfill on every chain, so it heads the
/// migrations no chain has run yet. On 0G the backfill records the earlier history record-only first
/// (`LibStoxMigrations.withoutHistory`); every other chain records this as the record alone.
/// @return The declaration.
function createZerogTokensDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.CREATE_ZEROG_TOKENS,
        onto: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
        history: false
    });
}

/// @title CreateZerogTokens
/// @notice Per-chain Safe bundle: on 0G, `StoxUnifiedDeployer@0_1_1.newTokenAndWrapperVault` for each of the next
/// `BATCH_SIZE` production token rows not yet created, with the token-owner Safe as the vault's initial owner, then
/// `setAuthorizer` to the row's region authoriser clone and `transferOwnership` to the chain's governance timelock;
/// in the bundle that creates the last row, this migration's root-line record; elsewhere the record alone.
/// @dev The 0.1.1 beacon-set deployer creates each receipt and vault itself and wires them in one call, which a plain
/// beacon proxy suite cannot. Row `i` is the deployers' `i`th creation, so the rows created so far are read from their
/// nonces, and any other use of the deployers is refused. A MultiSend cannot read a return value, so the bundle
/// addresses each new vault at the address its deployer's nonce predicts. Each bundle opens with an `initialize` probe
/// at its first predicted vault and wrapper: an empty address accepts the call, and any contract a deployer has
/// already created there refuses it, so a creation that lands between authoring and execution reverts the whole
/// bundle. Each vault is the Safe's only inside its own bundle: the bundle hands it to the timelock before it ends, so
/// the delay governs it from then on and nothing is minted before that.
contract CreateZerogTokens is SafeBundleScript, IStoxScript {
    /// @notice Rows per bundle. A row's three entries cost about 0.75M gas, so a full batch uses about 15M: well
    /// under 0G's 36M block, and under the 16.7M per-transaction cap of EIP-7825 if 0G adopts it.
    uint256 internal constant BATCH_SIZE = 20;

    /// @notice Bundle entries per row: the creation, `setAuthorizer` and `transferOwnership`.
    uint256 internal constant TXS_PER_ROW = 3;

    /// @notice Bundle entries before the first row: the vault and wrapper `initialize` probes.
    uint256 internal constant PROBE_COUNT = 2;

    /// @notice The receipt-vault beacon-set deployer's nonce before its first token: its constructor's two beacons.
    uint256 internal constant VAULT_DEPLOYER_FIRST_NONCE = 3;

    /// @notice The wrapper beacon-set deployer's nonce before its first wrapper.
    uint256 internal constant WRAPPER_DEPLOYER_FIRST_NONCE = 1;

    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return createZerogTokensDeclaration();
    }

    /// @notice This script's declaration.
    /// @return The declaration.
    function declared() internal pure returns (ScriptDeclaration memory) {
        return createZerogTokensDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: create the 0G production tokens through the audited 0.1.1 unified deployer";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261119-create-zerog-tokens-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice The rows this migration creates: on 0G, Ethereum's creation sequence, so each 0G address is the token
    /// Ethereum and HyperEVM hold at the same deployer nonce; none elsewhere.
    /// @return The configs.
    function configs() internal view returns (TokenConfig[] memory) {
        if (block.chainid != LibSafeInvariants.ZEROG_CHAIN_ID) return new TokenConfig[](0);
        return LibProdTokenConfig.zerogTokenConfigs();
    }

    /// @notice The authoriser row `row`'s vault is pointed at: the chain's EU clone for an EU row, its V4 clone
    /// otherwise.
    /// @param row The row's config.
    /// @return The authoriser.
    function authoriserFor(TokenConfig memory row) internal view returns (address) {
        return row.region == Region.EU
            ? LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
            : LibAuthoriserInvariants.authoriserForChainId(block.chainid);
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = address(safe());
        LibStoxMigrations.assertNext(declared(), chainSafe);
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        if (block.chainid != LibSafeInvariants.ZEROG_CHAIN_ID) return;

        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_1
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1
        );
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1
        );
        // The 0.1.30 vault's `fallback()` delegatecalls the facet, and a facet with no code silently no-ops.
        LibClosureInvariants.assertClosureContract(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_30
        );
        assertBeacons();
        assertAuthorisers();

        TokenConfig[] memory rows = configs();
        uint256 created = createdCount(rows.length);
        assertCreated(rows, created, created);
        TokenInstance[] memory table = zerogTable();
        if (table.length != rows.length) revert ZerogTokenTableLengthMismatch(table.length, rows.length);
        for (uint256 i = 0; i < rows.length; i++) {
            if (
                keccak256(bytes(table[i].underlying)) != keccak256(bytes(rows[i].underlying))
                    || table[i].receipt != address(0) || table[i].receiptVault != address(0)
                    || table[i].wrappedTokenVault != address(0)
            ) {
                revert ZerogTokenRowNotPlaceholder(i);
            }
        }
    }

    /// @notice Reverts unless the in-use beacons (the three token beacons: 0G runs no orchestrator) are owned by the
    /// timelock and each serves the implementation every other 0.1.1 chain serves.
    function assertBeacons() internal view {
        LibBeaconInvariants.assertProdBeaconsOwnedBy(block.chainid, timelock());
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(block.chainid);
        bytes32[4] memory codehashes = LibBeaconInvariants.prodBeaconCodehashesForChainId(block.chainid);
        for (uint256 i = 0; i <= LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beacons[i], timelock(), impls[i], codehashes[i]);
        }
    }

    /// @notice Reverts unless both pinned authoriser clones are deployed with the clone code hash, hold the role maps
    /// `LibIdealRoles` expects of them on 0G with the timelock as admin, grant the orchestrator's pinned address no
    /// role, and leave the Safe that initialised them no admin role.
    /// @dev Both pins are CloneFactory 0.1.15 open-salt addresses over the 0G Safe as initial admin, so the code hash
    /// proves the implementation and the address proves the init data, whoever deployed the clone. These checks prove
    /// the listed grants and the absence of the Safe's admin roles and the orchestrator's roles. The access control is
    /// not enumerable, so they cannot prove that no other account holds a role.
    function assertAuthorisers() internal view {
        address us = LibAuthoriserInvariants.activeChainAuthoriser();
        LibAuthoriserInvariants.assertEuAuthoriserDeployed(block.chainid);
        address eu = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        LibAuthoriserInvariants.assertHeld(
            us, LibAuthoriserInvariants.expectedGrantsOn(block.chainid, address(safe()), timelock())
        );
        LibAuthoriserInvariants.assertExpectedEuGrants(eu, timelock(), LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        assertNoSafeAdmin(us);
        assertNoSafeAdmin(eu);
        assertNoOrchestratorGrant(us);
        assertNoOrchestratorGrant(eu);
    }

    /// @notice Reverts if `authoriser` grants the orchestrator's pinned address `DEPOSIT` or `WITHDRAW`.
    /// @param authoriser The clone.
    function assertNoOrchestratorGrant(address authoriser) internal view {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(address(safe()), timelock());
        for (uint256 i = LibAuthoriserInvariants.ORCHESTRATOR_GRANT_INDEX; i < grants.length; i++) {
            if (IAccessControl(authoriser).hasRole(grants[i].role, grants[i].grantee)) {
                revert ZerogOrchestratorGranted(authoriser, grants[i].role);
            }
        }
    }

    /// @notice Reverts if the Safe holds `DEFAULT_ADMIN_ROLE` or any of the seven `_ADMIN` roles on `authoriser`.
    /// @param authoriser The clone.
    function assertNoSafeAdmin(address authoriser) internal view {
        address chainSafe = address(safe());
        if (IAccessControl(authoriser).hasRole(bytes32(0), chainSafe)) {
            revert ZerogAuthoriserSafeAdmin(authoriser, bytes32(0));
        }
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(chainSafe, timelock());
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            if (IAccessControl(authoriser).hasRole(grants[i].role, chainSafe)) {
                revert ZerogAuthoriserSafeAdmin(authoriser, grants[i].role);
            }
        }
    }

    /// @notice How many rows the deployers have created, refusing any creation that is not one of them.
    /// @param rowCount The number of rows.
    /// @return The number of rows created.
    function createdCount(uint256 rowCount) internal view returns (uint256) {
        if (rowCount == 0) return 0;
        uint256 vaultNonce = vm.getNonce(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        uint256 wrapperNonce = vm.getNonce(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        if (
            vaultNonce < VAULT_DEPLOYER_FIRST_NONCE || wrapperNonce < WRAPPER_DEPLOYER_FIRST_NONCE
                || (vaultNonce - VAULT_DEPLOYER_FIRST_NONCE) % 2 != 0
        ) {
            revert ZerogDeployersOutOfStep(vaultNonce, wrapperNonce);
        }
        uint256 created = (vaultNonce - VAULT_DEPLOYER_FIRST_NONCE) / 2;
        if (wrapperNonce - WRAPPER_DEPLOYER_FIRST_NONCE != created || created > rowCount) {
            revert ZerogDeployersOutOfStep(vaultNonce, wrapperNonce);
        }
        return created;
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        TokenConfig[] memory rows = configs();
        uint256 first = createdCount(rows.length);
        uint256 end = first + BATCH_SIZE < rows.length ? first + BATCH_SIZE : rows.length;
        bool last = end == rows.length;
        uint256 probes = end > first ? PROBE_COUNT : 0;
        SafeTx[] memory txs = new SafeTx[](probes + (end - first) * TXS_PER_ROW + (last ? 1 : 0));
        if (probes > 0) {
            TokenInstance memory next = token(rows[first], first);
            txs[0] = callTx(next.receiptVault, abi.encodeCall(ICloneableV2.initialize, ("")));
            txs[1] = callTx(next.wrappedTokenVault, abi.encodeCall(ICloneableV2.initialize, ("")));
        }
        for (uint256 i = first; i < end; i++) {
            uint256 at = probes + (i - first) * TXS_PER_ROW;
            address vault = token(rows[i], i).receiptVault;
            txs[at] = callTx(
                LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1,
                abi.encodeCall(
                    IStoxUnifiedDeployerV1.newTokenAndWrapperVault,
                    (OffchainAssetReceiptVaultConfigV2({
                            initialAdmin: address(safe()),
                            receiptVaultConfig: ReceiptVaultConfigV2({
                                asset: address(0), name: rows[i].name, symbol: rows[i].symbol, receipt: address(0)
                            })
                        }))
                )
            );
            txs[at + 1] = callTx(
                vault, abi.encodeCall(OffchainAssetReceiptVault.setAuthorizer, (IAuthorizeV1(authoriserFor(rows[i]))))
            );
            txs[at + 2] = callTx(vault, abi.encodeCall(Ownable.transferOwnership, (timelock())));
        }
        if (last) txs[txs.length - 1] = LibStoxMigrations.recordTx(declared());
        return txs;
    }

    /// @notice 0G's token table, which the pre-flight holds to placeholders in creation order.
    /// @dev Virtual so a test can stand in another table.
    /// @return The table.
    function zerogTable() internal view virtual returns (TokenInstance[] memory) {
        return LibTokenInvariants.productionTokensZerog();
    }

    /// @notice A value-free CALL bundle entry.
    /// @param to The target.
    /// @param data The calldata.
    /// @return The entry.
    function callTx(address to, bytes memory data) internal pure returns (SafeTx memory) {
        return SafeTx({to: to, value: 0, data: data, operation: Enum.Operation.Call});
    }

    /// @notice Row `i`'s token: the receipt-vault beacon-set deployer's `i`th receipt and vault and the wrapper
    /// beacon-set deployer's `i`th wrapper.
    /// @param row The row's config.
    /// @param i The row.
    /// @return The token.
    function token(TokenConfig memory row, uint256 i) internal pure returns (TokenInstance memory) {
        address vaultDeployer = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1;
        return TokenInstance({
            underlying: row.underlying,
            receipt: vm.computeCreateAddress(vaultDeployer, VAULT_DEPLOYER_FIRST_NONCE + 2 * i),
            receiptVault: vm.computeCreateAddress(vaultDeployer, VAULT_DEPLOYER_FIRST_NONCE + 2 * i + 1),
            wrappedTokenVault: vm.computeCreateAddress(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1, WRAPPER_DEPLOYER_FIRST_NONCE + i
            )
        });
    }

    /// @notice Reverts unless each of the first `count` rows is created as `assertToken` expects, the rows from
    /// `fresh` on also empty. Rows from an earlier bundle can hold supply: their authorisers let holders mint.
    /// @param rows The rows.
    /// @param count How many are created.
    /// @param fresh The first row the bundle under check creates.
    function assertCreated(TokenConfig[] memory rows, uint256 count, uint256 fresh) internal view {
        bytes32[4] memory proxyCodehashes = LibBeaconInvariants.prodTokenProxyCodehashesForChainId(block.chainid);
        for (uint256 i = 0; i < count; i++) {
            assertToken(rows[i], token(rows[i], i), proxyCodehashes, i >= fresh);
        }
    }

    /// @notice The first row the bundle that took creation to `created` rows created. Every bundle starts at a
    /// multiple of `BATCH_SIZE`, since each creates `BATCH_SIZE` rows or the rest.
    /// @param created How many rows are created.
    /// @return The row.
    function bundleStart(uint256 created) internal pure returns (uint256) {
        return created == 0 ? 0 : created - 1 - (created - 1) % BATCH_SIZE;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        TokenConfig[] memory rows = configs();
        uint256 created = createdCount(rows.length);
        if (created == rows.length) {
            LibStoxMigrations.assertRecorded(declared());
        } else {
            bytes32 lineHead = LibStoxMigrations.head();
            if (lineHead != declared().onto) revert ZerogTokensRecordedEarly(lineHead);
        }
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
        if (block.chainid != LibSafeInvariants.ZEROG_CHAIN_ID) return;
        assertBeacons();
        assertAuthorisers();
        assertCreated(rows, created, bundleStart(created));
    }

    /// @notice Reverts unless `created` is the beacon proxy triple for `row`, wired together, owned by the timelock, on
    /// its region's authoriser, named from `row` (the wrapper and receipt by the names they derive from the vault) and,
    /// if `empty`, with no supply.
    /// @param row The token's config row.
    /// @param created The created token.
    /// @param proxyCodehashes The chain's token proxy code hashes.
    /// @param empty Whether the vault and wrapper must have no supply.
    function assertToken(
        TokenConfig memory row,
        TokenInstance memory created,
        bytes32[4] memory proxyCodehashes,
        bool empty
    ) internal view {
        string memory underlying = row.underlying;
        if (created.receipt.codehash != proxyCodehashes[LibBeaconInvariants.RECEIPT_BEACON_INDEX]) {
            revert ZerogTokenMismatch(underlying, "receipt proxy");
        }
        if (created.receiptVault.codehash != proxyCodehashes[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]) {
            revert ZerogTokenMismatch(underlying, "vault proxy");
        }
        if (created.wrappedTokenVault.codehash != proxyCodehashes[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX])
        {
            revert ZerogTokenMismatch(underlying, "wrapper proxy");
        }
        if (address(IReceiptVaultV3(payable(created.receiptVault)).receipt()) != created.receipt) {
            revert ZerogTokenMismatch(underlying, "vault receipt");
        }
        if (IReceiptV3(created.receipt).manager() != created.receiptVault) {
            revert ZerogTokenMismatch(underlying, "receipt manager");
        }
        if (IERC4626(created.wrappedTokenVault).asset() != created.receiptVault) {
            revert ZerogTokenMismatch(underlying, "wrapper asset");
        }
        if (Ownable(created.receiptVault).owner() != timelock()) revert ZerogTokenMismatch(underlying, "owner");
        if (IAuthorisable(created.receiptVault).authorizer() != authoriserFor(row)) {
            revert ZerogTokenMismatch(underlying, "authoriser");
        }
        if (keccak256(bytes(IERC20Metadata(created.receiptVault).name())) != keccak256(bytes(row.name))) {
            revert ZerogTokenMismatch(underlying, "name");
        }
        if (keccak256(bytes(IERC20Metadata(created.receiptVault).symbol())) != keccak256(bytes(row.symbol))) {
            revert ZerogTokenMismatch(underlying, "symbol");
        }
        if (
            keccak256(bytes(IERC20Metadata(created.wrappedTokenVault).name()))
                != keccak256(bytes(string.concat("Wrapped ", row.name)))
        ) {
            revert ZerogTokenMismatch(underlying, "wrapper name");
        }
        if (
            keccak256(bytes(IERC20Metadata(created.wrappedTokenVault).symbol()))
                != keccak256(bytes(string.concat("w", row.symbol)))
        ) {
            revert ZerogTokenMismatch(underlying, "wrapper symbol");
        }
        if (
            keccak256(bytes(IReceiptV3(created.receipt).symbol()))
                != keccak256(bytes(string.concat(row.symbol, " RCPT")))
        ) {
            revert ZerogTokenMismatch(underlying, "receipt symbol");
        }
        if (!empty) return;
        if (IERC20Metadata(created.receiptVault).totalSupply() != 0) {
            revert ZerogTokenMismatch(underlying, "vault supply");
        }
        if (IERC20Metadata(created.wrappedTokenVault).totalSupply() != 0) {
            revert ZerogTokenMismatch(underlying, "wrapper supply");
        }
    }
}
