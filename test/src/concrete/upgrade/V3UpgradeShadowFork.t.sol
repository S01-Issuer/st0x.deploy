// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";

import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibProdDeployCurrent} from "../../../../src/generated/LibProdDeployCurrent.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibSafeOps, IUpgradeableBeacon} from "../../../../src/lib/LibSafeOps.sol";
import {
    ICorporateActionsV1,
    ACTION_TYPE_STOCK_SPLIT_V1,
    VALID_ACTION_TYPES_MASK
} from "../../../../src/interface/ICorporateActionsV1.sol";
import {CompletionFilter} from "../../../../src/lib/LibCorporateActionNode.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.1/src/interface/IReceiptVaultV3.sol";
import {IReceiptV3} from "rain-vats-0.2.1/src/interface/IReceiptV3.sol";
import {IAuthorizableV1} from "rain-vats-0.2.1/src/interface/IAuthorizableV1.sol";
import {IAuthorizeV1} from "rain-vats-0.2.1/src/interface/IAuthorizeV1.sol";
import {ICertifiableV1} from "rain-vats-0.2.1/src/interface/ICertifiableV1.sol";
import {ERC1967_BEACON_SLOT} from "rain-extrospection-0.1.14/src/lib/LibExtrospectERC1967BeaconProxy.sol";

/// @title V3UpgradeShadowForkTest
/// @notice Shadow-fork verification of the receipt vault V3 upgrade against
/// live production tokens. `setUp()` forks Base at head and applies the V3
/// upgrade to the fork; each test then exercises a behaviour against a real
/// on-chain receipt vault in the upgraded state: corporate-action fallback
/// routing, backwards-compatible reads, authoriser wiring, receipt wiring and
/// certification.
///
/// @dev The upgrade is applied to the fork in three steps:
///
/// 1. The V3 receipt vault implementation and the corporate-actions facet
///    are planted at their deterministic Zoltu addresses via `deployCodeTo`,
///    which runs their constructors at the target addresses so the facet's
///    `_SELF` immutable resolves to the address the vault's `fallback()`
///    delegatecalls into.
/// 2. The receipt vault beacon is asserted Safe-owned.
/// 3. `vm.prank(safe); beacon.upgradeTo(V3 impl)` upgrades the beacon, so
///    every live receipt vault behind it runs V3 code.
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
        // The vault bakes `LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET`
        // into its `fallback()`, so the facet is planted at that address.
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET
        );

        // 2. The live beacon is Safe-owned.
        assertEq(
            Ownable(BEACON).owner(),
            LibBeaconInvariants.PROD_BEACON_OWNER,
            "live beacon not Safe-owned - migration state regressed?"
        );

        // 3. Apply the upgrade: the Safe points the beacon at the V3 impl.
        vm.prank(LibBeaconInvariants.PROD_BEACON_OWNER);
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
        assertEq(Ownable(BEACON).owner(), LibBeaconInvariants.PROD_BEACON_OWNER, "beacon Safe-owned");
        assertEq(IBeacon(BEACON).implementation(), LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1, "beacon at V3 impl");
        assertEq(beaconOf(LIVE_RECEIPT_VAULT), BEACON, "live vault behind the upgraded beacon");
    }

    /// @notice Corporate-action selectors on a live receipt vault route into
    /// the facet via the vault's fallback delegatecall. `completedActionCount()`
    /// is not a selector on the vault itself, so a non-reverting read proves
    /// the wiring. A live vault with no corporate actions returns 0.
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
    /// `manager()` is the vault.
    function testReceiptWiringPreservedOnLiveVault() external view {
        IReceiptV3 receipt = IReceiptVaultV3(payable(LIVE_RECEIPT_VAULT)).receipt();
        assertEq(address(receipt), LIVE_RECEIPT, "receipt address preserved");
        assertEq(receipt.manager(), LIVE_RECEIPT_VAULT, "receipt manager is the vault");
    }

    /// @notice Certification is unchanged by the upgrade: the live vault is
    /// still within its certification window at the fork timestamp.
    function testCertificationUnchangedOnLiveVault() external view {
        assertFalse(
            ICertifiableV1(LIVE_RECEIPT_VAULT).isCertificationExpired(),
            "live vault still within certification window post-upgrade"
        );
    }

    /// @notice The wrapped token vault (not upgraded; its beacon is untouched)
    /// still reports the receipt vault as its ERC-4626 asset.
    function testWrappedVaultStillReferencesReceiptVault() external view {
        assertEq(
            IReceiptVaultV3(payable(LIVE_WRAPPED_VAULT)).asset(),
            LIVE_RECEIPT_VAULT,
            "wrapped vault still references the receipt vault"
        );
    }
}
