// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.20/src/abstract/OffchainAssetReceiptVault.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";

import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {IAuthorisable} from "../src/interface/IAuthorisable.sol";
import {IOwnable} from "../src/interface/IOwnable.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTokenInvariants} from "../src/lib/LibTokenInvariants.sol";

/// @notice The tQSEP vault's `authorizer()` is neither the V3 clone nor the
/// fleet authoriser.
/// @param authoriser The vault's authoriser.
error QsepUnexpectedAuthoriser(address authoriser);

/// @notice The tQSEP vault is not owned by the token-owner Safe, so the Safe
/// cannot call `setAuthorizer` on it.
/// @param owner The vault's owner.
error QsepVaultNotOwnedBySafe(address owner);

/// @notice The fleet authoriser's code hash is not the pinned V4 clone's.
/// @param actual The code hash on chain.
error FleetAuthoriserCodehashMismatch(bytes32 actual);

/// @notice The orchestrator does not hold `role` on the fleet authoriser, so
/// it could not mint or burn tQSEP after the swap.
/// @param role The missing role.
error OrchestratorLacksFleetRole(bytes32 role);

/// @notice After the Safe transaction the vault is not on the fleet authoriser.
/// @param authoriser The vault's authoriser.
error QsepNotOnFleetAuthoriser(address authoriser);

/// @notice The root line already holds this script's record.
/// @param id The migration id.
error QsepSetFleetAuthoriserRecorded(bytes32 id);

/// @notice This script's declaration: the Safe's record, after the
/// service-signer revoke's execution record.
/// @return The declaration.
function qsepSetFleetAuthoriserDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER,
        onto: LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER,
        history: false
    });
}

/// @title QsepSetFleetAuthoriser
/// @notice Authors the token-owner Safe transaction that moves the tQSEP vault
/// (`LibTokenInvariants.QSEP_RECEIPT_VAULT`, Base only) from the V3 authoriser
/// clone onto the fleet authoriser `LibAuthoriserInvariants.STOX_PROD_AUTHORISER`:
/// one CALL of `setAuthorizer(STOX_PROD_AUTHORISER)` to the vault, value 0. The
/// vault's `owner()` is still the Safe, so this is a direct Safe transaction,
/// with no timelock delay (see `docs/TIMELOCK.md`).
///
/// The bundle depends on live state, so a dispatch authors one of two bundles:
///
/// - Base, vault on the V3 clone: the `setAuthorizer` call ALONE. The root line
///   on Base is still at genesis (the V5 backfill has not executed), so the
///   record cannot ride with the call; it is written later by the next mode.
/// - Anywhere else (Base after the swap, and every other chain, where tQSEP
///   does not exist): the root-line record alone, once the line reaches this
///   script's onto.
///
/// So after the swap executes, a re-dispatch never authors the call again.
///
/// Both bundles are ONE transaction. The Safe Transaction Builder sends a
/// one-transaction batch as a direct CALL, not through `MultiSendCallOnly`, so
/// the logged hash is that CALL's `safeTxHash`, not a MultiSend hash.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261111-qsep-set-fleet-authoriser`, `network = base`. A signer
/// checks the downloaded artifact with
/// `forge script script/20261111-qsep-set-fleet-authoriser.s.sol --sig 'verify(string)' <path> --rpc-url base`.
contract QsepSetFleetAuthoriser is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return qsepSetFleetAuthoriserDeclaration();
    }

    /// @notice The Safe Transaction Builder `meta.name`.
    /// @return The name.
    function bundleName() internal view returns (string memory) {
        if (swapPending()) return "ST0x tQSEP: setAuthorizer to the fleet authoriser";
        return "ST0x migration record: qsep-set-fleet-authoriser";
    }

    /// @notice Where `run()` writes the Safe Transaction Builder JSON.
    /// @return The path.
    function artifactPath() internal view virtual returns (string memory) {
        return string.concat("out/20261111-qsep-set-fleet-authoriser-", vm.toString(block.chainid), ".json");
    }

    /// @notice The chain's token-owner Safe.
    /// @return The Safe.
    function safe() internal view returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice Whether this chain is Base and the tQSEP vault is still on the
    /// V3 clone: the state in which the bundle is the `setAuthorizer` call.
    /// @return True if the swap has not executed on Base.
    function swapPending() internal view returns (bool) {
        if (block.chainid != LibSafeInvariants.BASE_CHAIN_ID) return false;
        address authoriser = IAuthorisable(LibTokenInvariants.QSEP_RECEIPT_VAULT).authorizer();
        if (authoriser == LibAuthoriserInvariants.STOX_PROD_AUTHORISER_V3_CLONE) return true;
        if (authoriser == LibAuthoriserInvariants.STOX_PROD_AUTHORISER) return false;
        revert QsepUnexpectedAuthoriser(authoriser);
    }

    /// @notice The `setAuthorizer(STOX_PROD_AUTHORISER)` calldata.
    /// @return The calldata.
    function setAuthorizerCalldata() internal pure returns (bytes memory) {
        return abi.encodeCall(
            OffchainAssetReceiptVault.setAuthorizer, (IAuthorizeV1(LibAuthoriserInvariants.STOX_PROD_AUTHORISER))
        );
    }

    /// @notice Reverts unless the bundle can be authored on this chain.
    function preflight() internal view {
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        if (swapPending()) {
            address owner = IOwnable(LibTokenInvariants.QSEP_RECEIPT_VAULT).owner();
            if (owner != chainSafe) revert QsepVaultNotOwnedBySafe(owner);
            address fleet = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;
            if (fleet.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH) {
                revert FleetAuthoriserCodehashMismatch(fleet.codehash);
            }
            IAccessControl access = IAccessControl(fleet);
            address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
            if (!access.hasRole(keccak256("DEPOSIT"), orchestrator)) {
                revert OrchestratorLacksFleetRole(keccak256("DEPOSIT"));
            }
            if (!access.hasRole(keccak256("WITHDRAW"), orchestrator)) {
                revert OrchestratorLacksFleetRole(keccak256("WITHDRAW"));
            }
            return;
        }
        bytes32 id = LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER;
        if (LibStoxMigrations.applied(id) != 0) revert QsepSetFleetAuthoriserRecorded(id);
        LibStoxMigrations.assertNext(qsepSetFleetAuthoriserDeclaration(), chainSafe);
    }

    /// @notice The bundle: one CALL, derived from live state.
    /// @return The transactions.
    function authorBundle() internal view returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](1);
        if (swapPending()) {
            txs[0] = SafeTx({
                to: LibTokenInvariants.QSEP_RECEIPT_VAULT,
                value: 0,
                data: setAuthorizerCalldata(),
                operation: Enum.Operation.Call
            });
        } else {
            txs[0] = LibStoxMigrations.recordTx(qsepSetFleetAuthoriserDeclaration());
        }
        return txs;
    }

    /// @notice Reverts unless the executed bundle produced its state.
    /// @param swap Whether the bundle was the `setAuthorizer` call.
    function assertPostState(bool swap) internal view {
        if (!swap) {
            LibStoxMigrations.assertRecorded(qsepSetFleetAuthoriserDeclaration());
            return;
        }
        address vault = LibTokenInvariants.QSEP_RECEIPT_VAULT;
        address authoriser = IAuthorisable(vault).authorizer();
        if (authoriser != LibAuthoriserInvariants.STOX_PROD_AUTHORISER) revert QsepNotOnFleetAuthoriser(authoriser);
        address owner = IOwnable(vault).owner();
        if (owner != address(safe())) revert QsepVaultNotOwnedBySafe(owner);
    }

    /// @notice Authors the bundle on the selected fork, executes it through the
    /// Safe at its live nonce and threshold, requires its post-state, writes
    /// the artifact and logs the hash the signers' devices show. Any artifact
    /// already at `artifactPath()` is removed first, so a refused run leaves
    /// nothing to sign.
    /// @return The transaction's `safeTxHash` at the nonce before execution.
    function run() external returns (bytes32) {
        string memory path = artifactPath();
        if (vm.exists(path)) vm.removeFile(path);
        preflight();
        bool swap = swapPending();
        string memory name = bundleName();
        SafeTx[] memory txs = authorBundle();
        Safe bundleSafe = safe();
        uint256 nonce = bundleSafe.nonce();
        bytes32 txHash = LibSafeTx.safeTxHash(bundleSafe, txs[0], nonce);
        LibSafeFork.execute(vm, bundleSafe, txs[0]);
        assertPostState(swap);
        string memory json = LibSafeTxBuilderJson.toJson(vm, address(bundleSafe), block.chainid, name, txs);
        vm.writeFile(path, json);
        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Safe:", address(bundleSafe));
        console2.log("Chain:", block.chainid);
        console2.log("Nonce:", nonce);
        console2.log("Transactions:", txs.length);
        console2.log("SafeTxHash (direct CALL, one-transaction batch):", vm.toString(txHash));
        console2.log("Artifact:", path);
        return txHash;
    }

    /// @notice Re-derives the bundle from live state and refuses an artifact
    /// whose chain, Safe or transaction differ from it, then logs and returns
    /// the hash at the live nonce.
    /// @param jsonPath The artifact to check.
    /// @return The transaction's `safeTxHash` at the live nonce.
    function verify(string calldata jsonPath) external view returns (bytes32) {
        preflight();
        SafeTx[] memory expected = authorBundle();
        Safe bundleSafe = safe();
        LibSafeTxBuilderJson.requireMatches(vm, vm.readFile(jsonPath), address(bundleSafe), expected);
        bytes32 txHash = LibSafeTx.safeTxHash(bundleSafe, expected[0], bundleSafe.nonce());
        console2.log("Artifact verified against live state.");
        console2.log("SafeTxHash (direct CALL, one-transaction batch):", vm.toString(txHash));
        return txHash;
    }
}
