// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {Clones} from "@openzeppelin-contracts-5.6.1/proxy/Clones.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.5/src/interface/ICloneableFactoryV3.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.5/src/lib/LibCloneFactoryDeploy.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.7/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

/// @notice The deterministic `CloneFactory` (rain-factory 0.1.5) has no code
/// at its pinned address on the active chain. It is Zoltu-deployed and
/// permissionless — deploy it (rain.factory `manual-sol-artifacts`) and rerun.
/// @param factory The pinned factory address with no code.
error DeterministicFactoryNotDeployed(address factory);

/// @notice The deterministic `CloneFactory` runtime codehash does not match
/// the rain-factory 0.1.5 pin. The address holds something other than the
/// audited factory.
error DeterministicFactoryCodehashMismatch(address factory, bytes32 expected, bytes32 actual);

/// @notice The V4 authoriser impl has no runtime code at its pin. The clone
/// would EIP-1167-proxy an empty account.
error DeterministicV4ImplNotDeployed(address impl);

/// @notice The V4 authoriser impl's runtime codehash drifted from the pin.
error DeterministicV4ImplCodehashMismatch(address impl, bytes32 expected, bytes32 actual);

/// @notice The factory's own prediction for `(impl, salt, deployer)` does not
/// land on the pinned migration target. The pin and the deploy inputs have
/// drifted apart; nothing may broadcast until they agree.
error PredictedCloneMismatch(address predicted, address pinned);

/// @notice Code already exists at the migration target but its codehash is
/// not the pinned EIP-1167 shape. The target address is occupied by something
/// other than the expected clone — unrecoverable by rerunning.
error TargetOccupiedByForeignCode(address target, bytes32 expected, bytes32 actual);

/// @notice The broadcasting key is not the pinned deterministic deployer. The
/// factory namespaces the CREATE2 salt by `msg.sender`, so broadcasting from
/// any other key would deploy to a different address than the pin.
error WrongDeterministicDeployer(address expected, address actual);

/// @notice The freshly-deployed clone did not land on the pinned target.
error CloneNotAtTarget(address clone, address target);

/// @notice The deployed clone's runtime codehash is not the pinned EIP-1167
/// shape for the V4 impl.
error DeterministicCloneCodehashMismatch(address clone, bytes32 expected, bytes32 actual);

/// @notice An `_ADMIN` role the authoriser's `initialize` auto-grants is
/// missing from the token-owner Safe on the fresh clone.
error SafeMissingAdminRole(bytes32 role, address safe);

/// @title DeployDeterministicV4AuthoriserClone
/// @notice Broadcast script that deploys the V4 authoriser clone at its
/// deterministic migration target (#292) on the active chain:
///
///   `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC`
///
/// The target is chain-invariant: the 0.1.5 `CloneFactory` and the V4 impl
/// are both Zoltu deploys (same address everywhere), and the salt/deployer
/// pair is pinned, so every chain's clone lands on the same address. The
/// script is idempotent per chain — it no-ops when the pinned clone already
/// occupies the target, so one workflow dispatch per chain converges.
///
/// `initialAdmin` is the active chain's token-owner Safe: the authoriser's
/// `initialize` auto-grants the seven `_ADMIN` roles straight to the Safe, so
/// the deployer never holds any role on the clone and no renounce ceremony is
/// needed. The clone is otherwise inert — no operational grants, and no vault
/// references it — until the migration (grant mirroring + `setAuthorizer` +
/// live-pin flip) executes as its own scripted step.
contract DeployDeterministicV4AuthoriserClone is Script {
    /// @notice Deploy the clone at the migration target, or no-op if it is
    /// already there. Pre-flight asserts the Safe, factory, impl, and
    /// prediction; post-state asserts landing address, EIP-1167 shape, and
    /// the Safe's admin grants.
    function run() external {
        // Pre-flight: the active chain's token-owner Safe is intact (also
        // gates the script to chains with prod config — anything else reverts
        // inside the invariant lib).
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);

        // Pre-flight: the deterministic factory is deployed with the audited
        // codehash.
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        if (factory.code.length == 0) revert DeterministicFactoryNotDeployed(factory);
        if (factory.codehash != LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH) {
            revert DeterministicFactoryCodehashMismatch(
                factory, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH, factory.codehash
            );
        }

        // Pre-flight: the V4 impl is deployed with the audited codehash.
        address impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        if (impl.code.length == 0) revert DeterministicV4ImplNotDeployed(impl);
        bytes32 implCodehash = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1;
        if (impl.codehash != implCodehash) {
            revert DeterministicV4ImplCodehashMismatch(impl, implCodehash, impl.codehash);
        }

        // Pre-flight: the factory's own prediction lands on the pin.
        address target = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC;
        address predicted = ICloneableFactoryV3(factory)
            .predictDeterministicAddress(
                impl,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER
            );
        if (predicted != target) revert PredictedCloneMismatch(predicted, target);

        // Idempotency: the pinned clone already occupies the target — done.
        // Any OTHER code at the target is unrecoverable by rerunning.
        if (target.code.length != 0) {
            if (target.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODEHASH) {
                revert TargetOccupiedByForeignCode(
                    target, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODEHASH, target.codehash
                );
            }
            console2.log("Deterministic V4 authoriser clone already at target; nothing to do.");
            console2.log("Target:", vm.toString(target));
            return;
        }

        vm.startBroadcast();

        // The factory namespaces the CREATE2 salt by `msg.sender`, so the
        // pinned target only holds for the pinned deployer.
        address deployer = msg.sender;
        if (deployer != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER) {
            revert WrongDeterministicDeployer(
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER, deployer
            );
        }

        address clone = ICloneableFactoryV3(factory)
            .cloneDeterministic(
                impl,
                abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: safe})),
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT
            );

        vm.stopBroadcast();

        if (clone != target) revert CloneNotAtTarget(clone, target);
        assertPostState(clone, safe);

        console2.log("==== DETERMINISTIC V4 AUTHORISER CLONE DEPLOYED ====");
        console2.log("Clone:", vm.toString(clone));
        console2.log("CloneCodehash:", vm.toString(clone.codehash));
        console2.log("====================================================");
    }

    /// @notice Post-state assertion: the clone carries the pinned EIP-1167
    /// runtime shape and the Safe holds every auto-granted `_ADMIN` role.
    /// Split from `run()` so tests can drive it against a clone they deployed
    /// under `vm.prank`.
    /// @param clone The freshly-deployed clone.
    /// @param safe The `initialAdmin` the seven `_ADMIN` roles landed on.
    function assertPostState(address clone, address safe) public view {
        bytes32 expectedCodehash = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODEHASH;
        if (clone.codehash != expectedCodehash) {
            revert DeterministicCloneCodehashMismatch(clone, expectedCodehash, clone.codehash);
        }

        bytes32[7] memory adminRoles = autoGrantedAdminRoles();
        for (uint256 i = 0; i < adminRoles.length; i++) {
            if (!IAccessControl(clone).hasRole(adminRoles[i], safe)) {
                revert SafeMissingAdminRole(adminRoles[i], safe);
            }
        }
    }

    /// @notice The seven `_ADMIN` roles the base + ST0x-override `initialize`
    /// grant to the supplied `initialAdmin` config, in `_grantRole` order.
    /// @return roles The seven role hashes.
    function autoGrantedAdminRoles() public pure returns (bytes32[7] memory roles) {
        roles[0] = keccak256("CERTIFY_ADMIN");
        roles[1] = keccak256("CONFISCATE_RECEIPT_ADMIN");
        roles[2] = keccak256("CONFISCATE_SHARES_ADMIN");
        roles[3] = keccak256("DEPOSIT_ADMIN");
        roles[4] = keccak256("WITHDRAW_ADMIN");
        roles[5] = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");
        roles[6] = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");
    }
}
