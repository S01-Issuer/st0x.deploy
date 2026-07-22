// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {ERC1167_PREFIX, ERC1167_SUFFIX} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1167Proxy.sol";
import {ICloneableFactoryV2} from "rain-factory-0.1.1/src/interface/ICloneableFactoryV2.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

/// @notice The V4 authoriser impl at
/// `LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1`
/// has no runtime code. Either the pin is stale or the impl has been
/// selfdestructed since the pin was written; either way the clone would
/// initialise against zero code.
error V4ImplNotDeployed(address impl);

/// @notice The V4 authoriser impl's runtime codehash does not match the pinned
/// value in `LibProdDeployV4`. Impl has been replaced with different code.
error V4ImplCodehashMismatch(address impl, bytes32 expected, bytes32 actual);

/// @notice The canonical `CloneFactory` from `rain-factory-0.1.1` is not
/// deployed at its pinned address. Zoltu deploy is missing on this network.
error CloneFactoryNotDeployed(address factory);

/// @notice The `CloneFactory` runtime codehash does not match the rain-factory
/// pin. The address at the pinned location is not the audited factory.
error CloneFactoryCodehashMismatch(address factory, bytes32 expected, bytes32 actual);

/// @notice The active chain's `LibProdDeployV4` clone pin is already
/// hydrated. This script deploys a NEW clone — running it a second time would
/// produce a second clone the pin does not know about. Once hydrated, the
/// script is done for that chain.
error V4AuthoriserClonePinAlreadyHydrated(address pinned);

/// @notice This chain has no V4 authoriser clone pin in `LibProdDeployV4`, so
/// the script has no per-chain target to guard against. A typed revert rather
/// than a silent fallback to another chain's clone.
/// @param chainId The active chain id with no defined clone pin.
error V4AuthoriserCloneUnsupportedChain(uint256 chainId);

/// @notice The freshly-deployed clone's runtime codehash does not match the
/// EIP-1167 minimal-proxy shape computed from the V4 impl. Either the factory
/// deployed something other than an EIP-1167 clone, or the impl embedded in
/// the proxy is not the pinned V4 impl.
error CloneCodehashMismatch(address clone, bytes32 expected, bytes32 actual);

/// @notice A `(role, grantee)` pair that `LibAuthoriserInvariants.
/// expectedGrants()` says must hold is missing on the freshly-configured
/// clone. Either the grantRole loop skipped it or a subsequent renounce
/// removed it.
error ExpectedGrantMissing(bytes32 role, address grantee);

/// @notice The broadcasting deployer key still holds an `_ADMIN` role after
/// the renounce loop. If it stayed put the deployer keeps root privileges
/// over that role's grant map — the exact escalation this transfer is
/// designed to close.
error DeployerStillHoldsAdminRole(bytes32 role, address deployer);

/// @notice `MIRROR_START_INDEX` is out of range for the
/// `LibAuthoriserInvariants.expectedGrants()` array. The hand-maintained
/// slice constants have drifted from the invariant lib.
error GrantsSliceOutOfRange(uint256 startIndex, uint256 sliceLength, uint256 gramGrantsLen);

/// @title DeployV4AuthoriserClone
/// @notice Broadcast script that:
///
///   1. Deploys a fresh V4 authoriser clone via `CloneFactory.clone`,
///      initialised with the deployer as `initialAdmin`. The SEVEN
///      `_ADMIN` roles the base + ST0x-override `initialize` auto-grant
///      (five base: CERTIFY / CONFISCATE_RECEIPT / CONFISCATE_SHARES /
///      DEPOSIT / WITHDRAW; two override: SCHEDULE_CORPORATE_ACTION /
///      CANCEL_CORPORATE_ACTION) therefore land on the deployer, not the
///      Safe.
///   2. Grants the six non-admin roles enumerated in
///      `LibAuthoriserInvariants.expectedGrants()` (indices
///      `MIRROR_START_INDEX ..`) to their pinned grantees. These are the
///      operational `DEPOSIT` / `WITHDRAW` / `CERTIFY` provisions.
///   3. Grants every auto-granted `_ADMIN` role (all seven) to the ST0x
///      token-owner Safe. This matches the shape the previous Safe-signed
///      flow produced (`initialAdmin = Safe` auto-granted all seven
///      directly), and keeps the corporate-action admin-holder question
///      open rather than deciding it here by omission.
///   4. Renounces every auto-granted `_ADMIN` role from the deployer.
///      Post-loop the Safe is sole admin; the deployer has no residual
///      power over the clone.
///
/// All four steps run under a single `vm.startBroadcast()` — the deploy
/// key executes them in sequence in one `forge script --broadcast`
/// invocation. Dispatched via `.github/workflows/manual-broadcast.yaml`,
/// which broadcasts as `secrets.PRIVATE_KEY` — the same CI-held deploy
/// key `manual-sol-artifacts.yaml` uses for Zoltu impl deploys. The Safe
/// never signs anything for this deploy: the whole clone-configuration
/// ceremony collapses into a workflow-dispatch broadcast matching the
/// impl-deploy pattern the ops flow already uses.
///
/// @dev Trust model. During the four-step sequence the deployer key
/// holds every `_ADMIN` role and could self-grant additional operational
/// roles or extra `_ADMIN` positions. The post-state assertion at the
/// end of `run()` closes the "deployer still holds an admin role" case
/// (step 4 verifier), but does NOT enumerate for UNEXPECTED grants
/// beyond `expectedGrants()`. A compromised deploy key could sneak in a
/// stray `DEPOSIT` role for an attacker-controlled address between
/// steps 1 and 4 and this script would not catch it.
///
/// The V4 upgrade + swap script (`20260623-upgrade-receipt-vaults-to-v4.
/// s.sol`) is the enforcement point that must catch that: its pre-flight
/// asserts `LibAuthoriserInvariants.assertExpectedGrants(clone)` before
/// pointing any production vault at this clone, so an unexpected grant
/// would surface there. An exhaustive "no grants outside the expected
/// map" check on `LibAuthoriserInvariants` is planned as a follow-up
/// (top of the migration stack) and will close this gap regardless of
/// dispatch mechanism.
contract DeployV4AuthoriserClone is Script {
    /// @notice The starting index of the non-admin grant slice inside
    /// `LibAuthoriserInvariants.expectedGrants()`. Indices 0..6 are the
    /// seven `_ADMIN` grants (five auto-granted by the base `initialize`
    /// on the freshly-cloned V4 authoriser, plus the two corporate-action
    /// admins the ST0x override adds — all transferred to the Safe by
    /// steps 3-4). Indices 7..12 are the operational grants (`DEPOSIT` /
    /// `WITHDRAW` / `CERTIFY` × service + Safe) this script mirrors in.
    uint256 internal constant MIRROR_START_INDEX = 7;

    /// @notice The number of non-admin grants this script mirrors in.
    uint256 internal constant MIRROR_COUNT = 6;

    /// @notice The number of `_ADMIN` roles the base + ST0x-override
    /// `initialize` auto-grant to `initialAdmin` (five base + two
    /// corporate-action admins from the override).
    uint256 internal constant AUTO_GRANTED_ADMIN_COUNT = 7;

    /// @notice The V4 authoriser clone pin for the active chain, selected by
    /// `block.chainid` from `LibProdDeployV4` — `address(0)` until that chain's
    /// clone is deployed and the pin hydrated. Reverts for any chain without a
    /// pin rather than falling back to another chain's clone (reading the wrong
    /// chain's clone is the catastrophic failure this guard exists to prevent).
    /// @return The active chain's clone pin.
    function activeChainClonePin() internal view returns (address) {
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        }
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        }
        revert V4AuthoriserCloneUnsupportedChain(block.chainid);
    }

    /// @notice Deploy + configure + admin-transfer the V4 authoriser clone
    /// in a single broadcast. Steps 1-4 in the contract-level NatSpec.
    /// Pre-flight covers the invariants the whole flow relies on: the
    /// Safe is intact, the V4 impl exists at the pin with the pinned
    /// codehash, the CloneFactory is deployed with its pinned codehash,
    /// and the clone pin is not already hydrated (this would be a
    /// second deploy on the same network).
    function run() external {
        // Pre-flight: resolve THIS chain's token-owner Safe and assert it is
        // in its expected state. Chain-aware (Base + Ethereum carry distinct
        // Safe addresses) — hardcoding Base's Safe would revert on Ethereum,
        // where that address has no code. Base is pinned exactly; other chains
        // are asserted for the same policy (order-insensitive owner set), the
        // identical assertion the scheduled CI pin runs per chain. If the Safe
        // has drifted, admin transfer would move power to a shape we no longer
        // recognise.
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid));

        // Pre-flight: the invariant map still lines up with the hand-
        // maintained slice constants.
        assertGrantsSliceInvariant();

        // Pre-flight: V4 impl deployed at the pinned address with the
        // pinned codehash. The clone will EIP-1167-proxy this address;
        // if it isn't there or has the wrong code, the clone would
        // either fail to initialise or initialise against attacker code.
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        assertV4ImplDeployed(v4Impl);

        // Pre-flight: the canonical `CloneFactory` is deployed with the
        // pinned codehash. A missing/replaced factory would either
        // revert or hand back a clone under attacker-supplied bytecode.
        address factoryAddr = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        assertCloneFactoryDeployed(factoryAddr);

        // Pre-flight: the clone pin is not already hydrated. If it is,
        // running this script would deploy a SECOND clone the lib
        // doesn't know about — same behaviour as re-running any
        // deterministic deploy after it has already landed.
        address pinned = activeChainClonePin();
        if (pinned != address(0)) revert V4AuthoriserClonePinAlreadyHydrated(pinned);

        // The grant map parameterised on THIS chain's Safe: the map's
        // STRUCTURE is chain-agnostic, but the Safe grantee slots must be the
        // active chain's Safe — the no-arg overload pins Base's Safe and
        // would provision the wrong Safe with the direct action roles here.
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants(address(safe));

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender
        // resolves to the broadcast address (from
        // `--private-key`/`--sender` in production). Captured here so
        // subsequent grants + renounces line up with the initialAdmin
        // baked into the clone's initialize call.
        address deployer = msg.sender;

        // Step 1: deploy the clone.
        //
        // `initialAdmin = deployer` means the seven `_ADMIN` auto-grants
        // land on `deployer` in this window. Steps 3-4 swap them onto
        // the Safe.
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: deployer}));
        address clone = ICloneableFactoryV2(factoryAddr).clone(v4Impl, initData);

        IAccessControl acl = IAccessControl(clone);

        // Step 2: mirror the six non-admin operational grants
        // (`DEPOSIT` / `WITHDRAW` / `CERTIFY` × service + Safe).
        for (uint256 i = 0; i < MIRROR_COUNT; i++) {
            RoleGrant memory grant = allGrants[MIRROR_START_INDEX + i];
            acl.grantRole(grant.role, grant.grantee);
        }

        // Step 3: grant each auto-granted `_ADMIN` role to the Safe —
        // all SEVEN (the five V3-era admins in `expectedGrants()[0..4]`
        // plus the two corporate-action admins only the V4 override
        // grants; the lib map doesn't carry those two yet). After this
        // loop both `deployer` and `safe` hold every `_ADMIN` role;
        // step 4 revokes the deployer's copy.
        bytes32[AUTO_GRANTED_ADMIN_COUNT] memory adminRoles = autoGrantedAdminRoles();
        for (uint256 i = 0; i < adminRoles.length; i++) {
            acl.grantRole(adminRoles[i], address(safe));
        }

        // Step 4: renounce each auto-granted `_ADMIN` role from the
        // deployer. `renounceRole` requires `msg.sender == account`,
        // which holds because we are broadcasting as `deployer`.
        for (uint256 i = 0; i < adminRoles.length; i++) {
            acl.renounceRole(adminRoles[i], deployer);
        }

        vm.stopBroadcast();

        _assertPostState(clone, deployer, v4Impl);

        // Log the clone address prominently so the operator can copy it
        // into the post-execution pin PR (hydrate the active chain's
        // `LibProdDeployV4` clone pin — e.g. `STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM`;
        // the `..._CODEHASH` is already pinned in `LibProdDeployV4`).
        console2.log("==== V4 AUTHORISER CLONE DEPLOYED ====");
        console2.log("Clone:", vm.toString(clone));
        console2.log("CloneCodehash:", vm.toString(clone.codehash));
        console2.log("======================================");
    }

    /// @notice Post-state assertion invoked after the deploy sequence.
    /// Asserts the clone's EIP-1167 shape, every pinned expected grant
    /// holds, and the deployer no longer holds any auto-granted admin
    /// role. Split from `run()` so tests can call it against a clone
    /// they configured under `vm.startPrank`.
    /// @param clone The freshly-configured clone.
    /// @param deployer The address that broadcast the sequence — must
    /// hold no `_ADMIN` role post-renounce.
    /// @param v4Impl The pinned V4 impl the clone proxies; the expected
    /// codehash is re-derived from this address so the check does not
    /// depend on the (still-placeholder) codehash pin.
    function _assertPostState(address clone, address deployer, address v4Impl) internal view {
        // EIP-1167 shape + embedded impl match what the pinned V4 impl
        // produces.
        bytes32 expectedCloneCodehash = computeMinimalProxyCodehash(v4Impl);
        bytes32 actualCloneCodehash = clone.codehash;
        if (actualCloneCodehash != expectedCloneCodehash) {
            revert CloneCodehashMismatch(clone, expectedCloneCodehash, actualCloneCodehash);
        }

        IAccessControl acl = IAccessControl(clone);

        // Resolve the active chain's Safe (Base + Ethereum differ) so the
        // post-state check asserts against the chain we actually broadcast
        // on, with the grant map parameterised on that Safe.
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants(safe);

        // Every `(role, grantee)` in the chain's 13-entry grant map holds:
        // all seven `_ADMIN` roles on the Safe (swapped there in step 3) AND
        // the six operational grants from step 2, in one sweep.
        for (uint256 i = 0; i < allGrants.length; i++) {
            if (!acl.hasRole(allGrants[i].role, allGrants[i].grantee)) {
                revert ExpectedGrantMissing(allGrants[i].role, allGrants[i].grantee);
            }
        }

        // The deployer holds none of the auto-granted `_ADMIN` roles.
        // If any survived step 4, the deployer key still has root
        // privileges over that role's grant map — closes the
        // "transitional trust window" for those specific roles.
        bytes32[AUTO_GRANTED_ADMIN_COUNT] memory adminRoles = autoGrantedAdminRoles();
        for (uint256 i = 0; i < adminRoles.length; i++) {
            if (acl.hasRole(adminRoles[i], deployer)) {
                revert DeployerStillHoldsAdminRole(adminRoles[i], deployer);
            }
        }
    }

    /// @notice The seven `_ADMIN` roles the base + ST0x-override
    /// `initialize` grant to the supplied `initialAdmin` config.
    /// Hand-listed (in source-order of the `_grantRole` calls in the
    /// impl) because the grant/renounce sequence operates on the
    /// TRANSIENT deployer-held roles, not the master map's Safe-held
    /// entries.
    /// @return roles The seven role hashes, in `_grantRole` order.
    function autoGrantedAdminRoles() internal pure returns (bytes32[AUTO_GRANTED_ADMIN_COUNT] memory roles) {
        roles[0] = keccak256("CERTIFY_ADMIN");
        roles[1] = keccak256("CONFISCATE_RECEIPT_ADMIN");
        roles[2] = keccak256("CONFISCATE_SHARES_ADMIN");
        roles[3] = keccak256("DEPOSIT_ADMIN");
        roles[4] = keccak256("WITHDRAW_ADMIN");
        roles[5] = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");
        roles[6] = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");
    }

    /// @notice Assert the V4 impl is deployed at the pinned address with
    /// the pinned codehash.
    /// @param impl The V4 impl address to check.
    function assertV4ImplDeployed(address impl) internal view {
        if (impl.code.length == 0) revert V4ImplNotDeployed(impl);
        bytes32 actual = impl.codehash;
        bytes32 expected = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1;
        if (actual != expected) revert V4ImplCodehashMismatch(impl, expected, actual);
    }

    /// @notice Assert the canonical CloneFactory is deployed at the
    /// rain-factory pin with the pinned codehash.
    /// @param factory The CloneFactory address to check.
    function assertCloneFactoryDeployed(address factory) internal view {
        if (factory.code.length == 0) revert CloneFactoryNotDeployed(factory);
        bytes32 actual = factory.codehash;
        bytes32 expected = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH;
        if (actual != expected) revert CloneFactoryCodehashMismatch(factory, expected, actual);
    }

    /// @notice Assert the invariant map's slice constants
    /// (`MIRROR_START_INDEX`, `MIRROR_COUNT`) still line up with
    /// `LibAuthoriserInvariants.expectedGrants()`. Trips
    /// `GrantsSliceOutOfRange` if the invariant map has grown or shrunk
    /// away from what this script expects.
    function assertGrantsSliceInvariant() internal pure {
        uint256 expectedLength = MIRROR_START_INDEX + MIRROR_COUNT;
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        if (allGrants.length != expectedLength) {
            revert GrantsSliceOutOfRange(MIRROR_START_INDEX, MIRROR_COUNT, allGrants.length);
        }
    }

    /// @notice Compute the EIP-1167 minimal-proxy runtime codehash for
    /// the supplied implementation. The OpenZeppelin `Clones` impl
    /// deploys this exact bytecode shape:
    /// `<ERC1167_PREFIX><impl><ERC1167_SUFFIX>`.
    /// @param impl The implementation address embedded in the minimal
    /// proxy.
    /// @return The keccak256 of the minimal-proxy runtime bytecode.
    function computeMinimalProxyCodehash(address impl) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(ERC1167_PREFIX, impl, ERC1167_SUFFIX));
    }
}
