// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {
    ST0xOrchestratorBeaconSetDeployer,
    ST0xOrchestratorBeaconSetDeployerConfig
} from "../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";

/// @dev Mirrors the DEPOSIT permission constant from
/// `rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol`
/// (not exported directly).
bytes32 constant DEPOSIT = keccak256("DEPOSIT");

/// @dev Mirrors the WITHDRAW permission constant.
bytes32 constant WITHDRAW = keccak256("WITHDRAW");

/// @title ST0xOrchestratorProdBaseTest
/// @notice End-to-end fork tests for `ST0xOrchestrator` against the live
/// production tMSTR receipt vault on Base. Every test runs against a
/// pinned Base mainnet fork (`LibTestProd.createSelectForkBase`) and
/// deploys a fresh orchestrator impl + deployer + clone bound to
/// `LibTokenInvariants.MSTR_RECEIPT_VAULT`, then grants it the
/// `DEPOSIT` + `WITHDRAW` roles on the production authoriser via
/// direct storage poke — the deployed authoriser at this fork pin uses
/// OZ 4.x legacy `AccessControl` layout with the `_roles` mapping at
/// slot 101, not the OZ-5 ERC-7201 namespace.
contract ST0xOrchestratorProdBaseTest is Test {
    /// @dev Slot of the `_roles` mapping in the OZ 4.x
    /// `AccessControlUpgradeable` layout used by the deployed
    /// authoriser at the pinned fork block. Confirmed empirically: the
    /// on-chain bytecode predates the OZ 5.x namespaced-storage
    /// migration.
    uint256 private constant OZ4_ROLES_SLOT = 101;

    /// @dev Rebased tStock unit — the production tMSTR uses 18 decimals
    /// like all Rain receipt vaults.
    uint256 private constant TSTOCK = 1e18;

    /// @dev Mirrors `ST0xOrchestrator.MINT_BURN_ROLE`. Cached as a
    /// constant so `vm.prank` sequences don't waste the prank on an
    /// external `orchestrator.MINT_BURN_ROLE()` view call before
    /// reaching the state-changing call.
    bytes32 private constant MINT_BURN_ROLE = keccak256("MINT_BURN");

    /// @dev Compute the storage slot for `_roles[role].members[account]`
    /// under the OZ 4.x `AccessControlUpgradeable` layout.
    function hasRoleSlot(bytes32 role, address account) internal pure returns (bytes32) {
        // `_roles` is at slot 101. `_roles[role]` is a `RoleData` struct
        // whose first field is `mapping(address => bool) members`.
        // Mapping element slot: keccak256(abi.encode(key, mappingSlot)).
        bytes32 roleSlot = keccak256(abi.encode(role, bytes32(OZ4_ROLES_SLOT)));
        // Inside `RoleData`, `members` is at offset 0 relative to
        // `roleSlot`. `_roles[role].members[account]` is then
        // keccak256(abi.encode(account, roleSlot)).
        return keccak256(abi.encode(account, roleSlot));
    }

    /// @dev Deploy a fresh orchestrator impl + deployer + clone bound
    /// to the live production tMSTR receipt vault, and grant the
    /// clone the `DEPOSIT` + `WITHDRAW` roles on the vault's authoriser.
    /// Returns the clone address.
    function deployClone(address owner) internal returns (ST0xOrchestrator, address) {
        ST0xOrchestrator impl = new ST0xOrchestrator();
        ST0xOrchestratorBeaconSetDeployer deployer = new ST0xOrchestratorBeaconSetDeployer(
            ST0xOrchestratorBeaconSetDeployerConfig({
                initialOwner: owner, initialOrchestratorImplementation: address(impl)
            })
        );
        address clone =
            deployer.deploy(OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT)), owner);
        return (ST0xOrchestrator(payable(clone)), clone);
    }

    /// @dev Grant `role` to `account` on `authorizer` via storage poke.
    /// Uses the OZ 4.x `_roles` mapping layout at slot 101.
    function pokeRole(address authorizer, bytes32 role, address account) internal {
        vm.store(authorizer, hasRoleSlot(role, account), bytes32(uint256(1)));
    }

    /// @notice Basic wiring: after deployment the clone's `vault`,
    /// `receipt`, `nextBurnReceiptId`, and `DEFAULT_ADMIN_ROLE`
    /// grantee all match the expected values.
    function testProdOrchestratorInitialState() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        assertEq(address(orchestrator.vault()), address(vault), "vault");
        assertEq(address(orchestrator.receipt()), address(vault.receipt()), "receipt");
        assertEq(orchestrator.nextBurnReceiptId(), 0, "nextBurnReceiptId");
        assertTrue(orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), owner), "default admin");
    }

    /// @notice Poking `DEPOSIT` on the live authoriser via slot 101
    /// makes `hasRole` return true — confirms the OZ 4.x layout
    /// assumption used throughout this suite.
    function testProdOrchestratorRolePokeVisibleToAuthorizer() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);
        address authorizer =
            address(OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT)).authorizer());

        assertFalse(IAccessControl(authorizer).hasRole(DEPOSIT, address(orchestrator)), "pre DEPOSIT");
        assertFalse(IAccessControl(authorizer).hasRole(WITHDRAW, address(orchestrator)), "pre WITHDRAW");

        pokeRole(authorizer, DEPOSIT, address(orchestrator));
        pokeRole(authorizer, WITHDRAW, address(orchestrator));

        assertTrue(IAccessControl(authorizer).hasRole(DEPOSIT, address(orchestrator)), "post DEPOSIT");
        assertTrue(IAccessControl(authorizer).hasRole(WITHDRAW, address(orchestrator)), "post WITHDRAW");
    }

    /// @notice Happy-path mint: MM calls `orchestrator.mint` and the
    /// recipient's rebased tStock balance grows by `amount`, the
    /// orchestrator holds no shares, and the orchestrator holds the
    /// newly-minted receipt at `highwaterId+1` (as observed before the
    /// mint) with balance `amount`.
    function testProdOrchestratorMintHappyPath() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address recipient = makeAddr("recipient");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        address authorizer = address(vault.authorizer());
        pokeRole(authorizer, DEPOSIT, address(orchestrator));
        pokeRole(authorizer, WITHDRAW, address(orchestrator));

        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        uint256 preRecipient = IERC20(address(vault)).balanceOf(recipient);
        uint256 preOrchestrator = IERC20(address(vault)).balanceOf(address(orchestrator));
        uint256 highwaterBefore = vault.highwaterId();
        uint256 amount = 5 * TSTOCK;

        vm.prank(mm);
        orchestrator.mint(recipient, amount);

        assertEq(IERC20(address(vault)).balanceOf(recipient) - preRecipient, amount, "recipient delta");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), preOrchestrator, "orchestrator shares");

        // The mint call increments `highwaterId` by 1 and mints the
        // receipt at the new id.
        uint256 mintedId = highwaterBefore + 1;
        assertEq(vault.highwaterId(), mintedId, "highwater advanced by 1");
        assertEq(IERC1155(address(vault.receipt())).balanceOf(address(orchestrator), mintedId), amount, "receipt bal");
    }

    /// @notice Happy-path burn: recipient approves, MM calls
    /// `orchestrator.burn(recipient, amount)`. Shares net to zero on
    /// both recipient and orchestrator, the receipt at the just-minted
    /// id is fully consumed, and `nextBurnReceiptId` advances past
    /// that id.
    function testProdOrchestratorBurnHappyPath() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address recipient = makeAddr("recipient");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        address authorizer = address(vault.authorizer());
        pokeRole(authorizer, DEPOSIT, address(orchestrator));
        pokeRole(authorizer, WITHDRAW, address(orchestrator));

        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        uint256 highwaterBefore = vault.highwaterId();
        uint256 amount = 3 * TSTOCK;

        vm.prank(mm);
        orchestrator.mint(recipient, amount);

        uint256 mintedId = highwaterBefore + 1;
        uint256 preRecipient = IERC20(address(vault)).balanceOf(recipient);
        assertEq(preRecipient, amount, "pre-burn recipient bal");

        vm.prank(recipient);
        IERC20(address(vault)).approve(address(orchestrator), amount);

        vm.prank(mm);
        orchestrator.burn(recipient, amount);

        assertEq(IERC20(address(vault)).balanceOf(recipient), 0, "post-burn recipient bal");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "post-burn orch bal");
        assertEq(IERC1155(address(vault.receipt())).balanceOf(address(orchestrator), mintedId), 0, "receipt consumed");
        // The walk consumed the receipt exactly, so the pointer sits
        // one past the consumed id.
        assertEq(orchestrator.nextBurnReceiptId(), mintedId + 1, "next pointer");
    }

    /// @notice Mint-on-demand: prime the burn pointer past the highest
    /// receipt the orchestrator holds so a small burn triggers the
    /// fallback mint. The pointer skips zero-balance ids until it hits
    /// the pinned vault's highwater, then the orchestrator mints a
    /// fresh receipt-backed batch to cover the shortfall — supply
    /// change nets to zero (mint then immediately redeem the same
    /// receipt).
    function testProdOrchestratorMintOnDemand() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address recipient = makeAddr("recipient");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        address authorizer = address(vault.authorizer());
        pokeRole(authorizer, DEPOSIT, address(orchestrator));
        pokeRole(authorizer, WITHDRAW, address(orchestrator));

        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        // Seed the recipient with a stranded balance transferred in
        // "from offchain" — we simulate this by minting to the
        // orchestrator and then transferring the shares out to the
        // recipient, but *setting the burn index past the receipt* so
        // the burn walk cannot find backing and must mint-on-demand.
        uint256 amount = 2 * TSTOCK;
        vm.prank(mm);
        orchestrator.mint(recipient, amount);

        // Push the burn pointer past every existing receipt on the
        // vault. Any subsequent `burn` must fall back to mint-on-demand
        // for the entire amount. `vault.highwaterId()` is cached out of
        // the pranked call so the prank targets `setBurnIndex` and not
        // the view.
        uint256 highwaterBefore = vault.highwaterId();
        vm.prank(owner);
        orchestrator.setBurnIndex(highwaterBefore + 1);

        uint256 supplyBefore = IERC20(address(vault)).totalSupply();

        vm.prank(recipient);
        IERC20(address(vault)).approve(address(orchestrator), amount);
        vm.prank(mm);
        orchestrator.burn(recipient, amount);

        // Mint-on-demand allocated a fresh id, so highwater grew by
        // exactly one.
        uint256 onDemandId = highwaterBefore + 1;
        assertEq(vault.highwaterId(), onDemandId, "highwater grew by 1");
        // The mint-on-demand cycle is net zero on supply: it minted
        // `amount` fresh shares to the orchestrator and then
        // immediately redeemed them against the freshly-issued
        // receipt.
        assertEq(IERC20(address(vault)).totalSupply(), supplyBefore, "supply net zero across mint-on-demand");
        // Recipient balance drained.
        assertEq(IERC20(address(vault)).balanceOf(recipient), 0, "recipient drained");
        // The freshly-minted on-demand receipt was fully consumed by
        // the redeem that immediately followed it.
        assertEq(
            IERC1155(address(vault.receipt())).balanceOf(address(orchestrator), onDemandId),
            0,
            "on-demand receipt consumed"
        );
        // The orchestrator now holds the `amount` of shares pulled off
        // the recipient. Those shares are the "interest accrued in
        // tStock form" the natspec calls out — every mint-on-demand
        // cycle strands the burn input on the orchestrator, to be
        // swept later by the issuer via `withdrawShares`.
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), amount, "orchestrator strand = burn input");
    }

    /// @notice Round-trip fuzz: mint N then burn N. Recipient and
    /// orchestrator share balances net to zero and the burn walk
    /// advances the pointer by exactly one (the single receipt was
    /// fully consumed).
    function testFuzzProdOrchestratorRoundTrip(uint256 amount) external {
        amount = bound(amount, 1, 100 * TSTOCK);
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address recipient = makeAddr("recipient");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        address authorizer = address(vault.authorizer());
        pokeRole(authorizer, DEPOSIT, address(orchestrator));
        pokeRole(authorizer, WITHDRAW, address(orchestrator));

        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        uint256 preRecipient = IERC20(address(vault)).balanceOf(recipient);
        uint256 preOrchestrator = IERC20(address(vault)).balanceOf(address(orchestrator));
        uint256 preNextBurn = orchestrator.nextBurnReceiptId();

        vm.prank(mm);
        orchestrator.mint(recipient, amount);

        vm.prank(recipient);
        IERC20(address(vault)).approve(address(orchestrator), amount);
        vm.prank(mm);
        orchestrator.burn(recipient, amount);

        assertEq(IERC20(address(vault)).balanceOf(recipient), preRecipient, "recipient net zero");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), preOrchestrator, "orch net zero");
        // The walk skipped every legacy zero-balance id up to and
        // including our freshly-minted receipt, then advanced one
        // past it — so the pointer sits at (minted id + 1).
        assertEq(orchestrator.nextBurnReceiptId(), vault.highwaterId() + 1, "next pointer one past highwater");
        // And it advanced strictly forwards.
        assertGt(orchestrator.nextBurnReceiptId(), preNextBurn, "pointer advanced");
    }
}
