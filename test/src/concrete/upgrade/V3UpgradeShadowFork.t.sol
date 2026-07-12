// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibSafeOps, IUpgradeableBeacon} from "../../../../src/lib/LibSafeOps.sol";
import {SCHEDULE_CORPORATE_ACTION} from "../../../../src/lib/LibCorporateAction.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.7/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.5/src/interface/ICloneableFactoryV3.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.5/src/lib/LibCloneFactoryDeploy.sol";
import {
    ICorporateActionsV1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    VALID_ACTION_TYPES_MASK
} from "../../../../src/interface/ICorporateActionsV1.sol";
import {CompletionFilter} from "../../../../src/lib/LibCorporateActionNode.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IReceiptVaultV3} from "rain-vats-0.1.7/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.1.7/src/interface/IReceiptV3.sol";
import {IAuthorizableV1} from "rain-vats-0.1.7/src/interface/IAuthorizableV1.sol";
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.7/src/interface/IAuthorizeV1.sol";
import {ICertifiableV1} from "rain-vats-0.1.7/src/interface/ICertifiableV1.sol";
import {ERC1967_BEACON_SLOT} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1967BeaconProxy.sol";

/// @title V3UpgradeShadowForkTest
/// @notice Shadow-fork verification of the receipt vault V3 upgrade against
/// LIVE production tokens. `setUp()` forks Base at head, applies the
/// beacon-ownership migration (PR-A) and the V3 upgrade (PR-B) to the fork,
/// then each test exercises a behaviour against a real on-chain receipt vault
/// in the upgraded state.
///
/// This is the "ideally we'd run the current behaviour against real tokens
/// with the upgrade applied" check: it targets the V3 deltas (corporate-action
/// fallback routing) plus the critical user paths that must survive the
/// upgrade (backwards-compat reads, authoriser wiring, receipt wiring,
/// certification). It is deliberately NOT a full mixin that re-runs every
/// existing test against the upgraded fork — that is a larger refactor worth
/// building only if many upgrades accumulate.
///
/// @dev The upgrade is applied to the fork via three cheatcode-driven steps,
/// each simulating an operational action that has not yet executed on-chain:
///
/// 1. **Plant V3 bytecode** — the V3 receipt vault implementation and the
///    corporate-actions facet are planted at their deterministic Zoltu
///    addresses via `deployCodeTo`, which runs their real constructors at the
///    target addresses. Running the facet's constructor at its production
///    address is required so its `_SELF` immutable resolves to
///    `STOX_CORPORATE_ACTIONS_FACET`; the vault's `fallback()` hardcodes that
///    address as its delegatecall target.
/// 2. **Beacon ownership** — the receipt vault beacon is transferred from the
///    rainlang.eth EOA to the Safe (PR-A's effect).
/// 3. **Upgrade** — `vm.prank(safe); beacon.upgradeTo(V3 impl)` upgrades the
///    beacon. Every live receipt vault behind the beacon now runs V3 code.
contract V3UpgradeShadowForkTest is Test {
    /// @notice The receipt vault beacon upgraded to V3.
    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    /// @notice A representative live production receipt vault behind the
    /// upgraded beacon. MSTR is the first entry in
    /// `LibTokenInvariants.productionReceiptVaults`.
    address internal constant LIVE_RECEIPT_VAULT = LibTokenInvariants.MSTR_RECEIPT_VAULT;

    /// @notice The live receipt (ERC-1155) paired with `LIVE_RECEIPT_VAULT`.
    address internal constant LIVE_RECEIPT = LibTokenInvariants.MSTR_RECEIPT;

    /// @notice The live wrapped token vault paired with `LIVE_RECEIPT_VAULT`.
    address internal constant LIVE_WRAPPED_VAULT = LibTokenInvariants.MSTR_WRAPPED_TOKEN_VAULT;

    function setUp() public {
        vm.createSelectFork(LibRainDeploy.BASE);

        // 1. Plant the V3 receipt vault implementation and the corporate-
        //    actions facet at their deterministic addresses, running their
        //    constructors there so the facet's `_SELF` and the vault's pinned
        //    facet target line up.
        deployCodeTo("src/concrete/StoxReceiptVault.sol:StoxReceiptVault", LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1);
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_1
        );

        // 2. Simulate PR-A: transfer the beacon from the EOA to the Safe.
        vm.prank(LibProdDeployV1.BEACON_INITIAL_OWNER);
        Ownable(BEACON).transferOwnership(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // 3. Apply the upgrade: the Safe points the beacon at the V3 impl.
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        IUpgradeableBeacon(BEACON).upgradeTo(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1);
    }

    /// @notice Read the EIP-1967 beacon address from a proxy contract. Mirrors
    /// `LibTokenInvariantsAddressesTest.beaconOf`.
    function beaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// @notice Sanity: the fork is in the upgraded state. The beacon is
    /// Safe-owned, points at the V3 implementation, and the live receipt vault
    /// is still behind this beacon.
    function testForkIsInUpgradedState() external view {
        assertEq(Ownable(BEACON).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "beacon Safe-owned");
        assertEq(IBeacon(BEACON).implementation(), LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1, "beacon at V3 impl");
        assertEq(beaconOf(LIVE_RECEIPT_VAULT), BEACON, "live vault behind the upgraded beacon");
    }

    /// @notice Headline V3 change: corporate-action selectors on a LIVE
    /// receipt vault route into the facet via the vault's fallback
    /// delegatecall. `completedActionCount()` is not a selector on the vault
    /// itself — it only resolves if the fallback forwards to the facet — so a
    /// non-reverting read proves the wiring. A fresh-to-corporate-actions
    /// live vault returns 0 completed actions.
    function testCorporateActionsFacetWiredOnLiveVault() external view {
        uint256 completed = ICorporateActionsV1(LIVE_RECEIPT_VAULT).completedActionCount();
        assertEq(completed, 0, "live vault has no completed corporate actions post-upgrade");
    }

    /// @notice The traversal getters route through the fallback and return the
    /// expected empty-list tuple on a live vault with no scheduled actions.
    /// Exercises the read path of the V3 facet end-to-end against real state.
    function testCorporateActionTraversalRoutesOnLiveVault() external view {
        (uint256 cursor, uint256 actionType, uint64 effectiveTime) =
            ICorporateActionsV1(LIVE_RECEIPT_VAULT).latestActionOfType(VALID_ACTION_TYPES_MASK, CompletionFilter.ALL);
        assertEq(cursor, type(uint256).max, "no action -> NODE_NONE cursor");
        assertEq(actionType, 0, "no action -> zero type");
        assertEq(effectiveTime, 0, "no action -> zero effectiveTime");
    }

    /// @notice Backwards-compat smoke: the ERC-20 metadata read surface of a
    /// live receipt vault is preserved post-upgrade. `decimals`, `name`, and
    /// `symbol` are reads integrators depend on; the V3 fallback must not
    /// shadow them. `asset()` is asserted `address(0)`: an offchain-asset
    /// receipt vault has no on-chain underlying ERC-20, and the upgrade must
    /// not change that.
    function testBackwardsCompatReadsOnLiveVault() external view {
        // decimals is pinned at 18 for prod vaults; the V3 impl must not change
        // the inherited ERC-20 metadata surface.
        assertEq(IERC20Metadata(LIVE_RECEIPT_VAULT).decimals(), 18, "decimals preserved");
        assertGt(bytes(IERC20Metadata(LIVE_RECEIPT_VAULT).name()).length, 0, "name still readable");
        assertGt(bytes(IERC20Metadata(LIVE_RECEIPT_VAULT).symbol()).length, 0, "symbol still readable");
        // An OffchainAssetReceiptVault holds an offchain asset, so `asset()`
        // is the zero address by design. The read must still resolve (not
        // route into the facet) and report zero — the upgrade does not wire an
        // on-chain underlying.
        assertEq(
            IReceiptVaultV3(payable(LIVE_RECEIPT_VAULT)).asset(), address(0), "offchain vault has no on-chain asset"
        );
    }

    /// @notice The ERC-20 token supply surface of a live receipt vault still
    /// reads post-upgrade. `totalSupply` and a `balanceOf` read are inherited
    /// ReceiptVault selectors (not facet selectors); the V3 fallback must not
    /// shadow them, and the corporate-action rebase logic the V3 impl adds must
    /// keep these resolving against real on-chain balances.
    function testSupplyReadsPreservedOnLiveVault() external view {
        // totalSupply resolves through the upgraded impl (rebased view). The
        // load-bearing property is that the call returns a defined value
        // without reverting or routing into the facet.
        uint256 supply = IERC20Metadata(LIVE_RECEIPT_VAULT).totalSupply();
        assertGe(supply, 0, "totalSupply returns a defined value");
        // balanceOf of the zero address is a stable, side-effect-free read that
        // exercises the rebased balance path on the upgraded impl.
        assertEq(IERC20Metadata(LIVE_RECEIPT_VAULT).balanceOf(address(0)), 0, "zero-address balance is zero");
    }

    /// @notice The authoriser is still wired on the live vault post-upgrade and
    /// resolves to a deployed contract. The V3 facet reads the vault's
    /// authoriser for corporate-action gating, so the upgrade must preserve the
    /// `authorizer()` accessor and its stored value.
    function testAuthorizerStillWiredOnLiveVault() external view {
        IAuthorizeV1 authorizer = IAuthorizableV1(LIVE_RECEIPT_VAULT).authorizer();
        assertTrue(address(authorizer) != address(0), "authorizer still set");
        assertTrue(address(authorizer).code.length > 0, "authorizer is a deployed contract");
    }

    /// @notice Receipt mint/burn wiring is preserved: the live vault's
    /// `receipt()` resolves to the paired ERC-1155, and that receipt's
    /// `manager()` is the vault. If this drifted, every deposit (mint receipt)
    /// and withdraw (burn receipt) on the live token would revert.
    function testReceiptWiringPreservedOnLiveVault() external view {
        IReceiptV3 receipt = IReceiptVaultV3(payable(LIVE_RECEIPT_VAULT)).receipt();
        assertEq(address(receipt), LIVE_RECEIPT, "receipt address preserved");
        assertEq(receipt.manager(), LIVE_RECEIPT_VAULT, "receipt manager is the vault");
    }

    /// @notice Certification is unchanged by the upgrade: the live vault is
    /// still within its certification window at the fork timestamp. The V3
    /// upgrade does not touch certification storage, so an expired flag here
    /// would signal the upgrade corrupted unrelated state.
    function testCertificationUnchangedOnLiveVault() external view {
        assertFalse(
            ICertifiableV1(LIVE_RECEIPT_VAULT).isCertificationExpired(),
            "live vault still within certification window post-upgrade"
        );
    }

    /// @notice The wrapped token vault wiring survives the upgrade: it still
    /// reports the receipt vault as its ERC-4626 asset. The wrapped vault is
    /// not upgraded (its beacon is untouched), but it depends on the receipt
    /// vault, so this confirms the receipt vault upgrade did not break the
    /// downstream wrapper's view of it.
    function testWrappedVaultStillReferencesReceiptVault() external view {
        assertEq(
            IReceiptVaultV3(payable(LIVE_WRAPPED_VAULT)).asset(),
            LIVE_RECEIPT_VAULT,
            "wrapped vault still references the receipt vault"
        );
    }

    /// @notice The OTHER half of the migration bundle — the `setAuthorizer`
    /// swap — actually re-wires authorisation on a LIVE receipt vault. The
    /// tests above cover the beacon (impl) leg; this covers the authoriser
    /// leg: deploy a fresh V4 corporate-action-aware authoriser clone,
    /// `setAuthorizer` the live vault onto it as the Safe owner, and prove the
    /// vault now gates through the new clone — a granted `SCHEDULE_CORPORATE_
    /// ACTION` caller is permitted, an ungranted caller is rejected with the
    /// exact `Unauthorized` error. The corporate-action permission is the V4
    /// delta: the pre-swap production authoriser configures no role admin for
    /// it, so only the swapped V4 clone can gate it.
    function testAuthoriserSwapReWiresGatingOnLiveVault() external {
        // Pre-swap: the live vault reports the current production authoriser.
        assertEq(
            address(IAuthorizableV1(LIVE_RECEIPT_VAULT).authorizer()),
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            "pre-swap authoriser is the live production authoriser"
        );

        // Deploy a fresh V4 authoriser clone. The impl `_disableInitializers`
        // in its constructor, so it must be cloned + initialised via the
        // CloneFactory — the same path the production clone-deploy broadcast
        // uses.
        address cloneAdmin = makeAddr("cloneAdmin");
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        address clone = ICloneableFactoryV3(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS)
            .cloneDeterministic(
                address(impl),
                abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: cloneAdmin})),
                bytes32(0)
            );

        // Grant the corporate-action scheduling role to one user. `cloneAdmin`
        // holds `SCHEDULE_CORPORATE_ACTION_ADMIN` from init (the V4 extension),
        // so it is the role admin able to grant `SCHEDULE_CORPORATE_ACTION`.
        address scheduler = makeAddr("scheduler");
        address outsider = makeAddr("outsider");
        vm.prank(cloneAdmin);
        IAccessControl(clone).grantRole(SCHEDULE_CORPORATE_ACTION, scheduler);

        // Swap: the Safe (vault owner) rewires the live vault onto the clone.
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        ISetAuthorizer(LIVE_RECEIPT_VAULT).setAuthorizer(IAuthorizeV1(clone));

        // The swap landed: the vault now routes authorisation through the clone.
        IAuthorizeV1 wired = IAuthorizableV1(LIVE_RECEIPT_VAULT).authorizer();
        assertEq(address(wired), clone, "post-swap authoriser is the new V4 clone");

        // The swapped authoriser gates corporate actions: the granted
        // scheduler is permitted (no revert)...
        wired.authorize(scheduler, SCHEDULE_CORPORATE_ACTION, "");
        // ...and an ungranted caller is rejected with the exact typed error.
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, outsider, SCHEDULE_CORPORATE_ACTION, bytes("")));
        wired.authorize(outsider, SCHEDULE_CORPORATE_ACTION, "");
    }

    // -------------------------------------------------------------------------
    // TODO(audit): enumerate v0.1.1 findings — pending report from Josh/DM.
    //
    // The v0.1.1 audit report is not in-repo at the time of writing. Once it
    // lands, add one focused behavioural test per finding addressed in V3,
    // hitting the specific path the finding relates to against the upgraded
    // live state above. Until then this shadow-fork suite covers the
    // structural and behavioural deltas (corporate-action fallback routing,
    // backwards-compat reads, authoriser/receipt wiring, certification) but
    // does NOT yet assert finding-by-finding remediation. Do not treat the
    // absence of this section's tests as evidence the findings are fixed.
    // -------------------------------------------------------------------------
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// owner-gated selector. Avoids dragging the full `OffchainAssetReceiptVault`
/// storage inheritance into this test just to encode one call.
interface ISetAuthorizer {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}
