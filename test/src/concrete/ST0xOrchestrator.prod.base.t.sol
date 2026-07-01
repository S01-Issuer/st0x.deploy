// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

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
        // Pointer seeds one past the live vault's current highwater so the
        // first burn never scans the vault's pre-existing id history.
        assertEq(orchestrator.nextBurnReceiptId(), vault.highwaterId() + 1, "nextBurnReceiptId");
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
        vm.recordLogs();
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
        // Pointer lands one past the fully-drained on-demand receipt
        // (`idx = cap` in the fallback, then `take == bal` bumps once).
        assertEq(orchestrator.nextBurnReceiptId(), onDemandId + 1, "pointer one past on-demand id");

        // Exactly one `BurnShortfallMinted` fired, covering the FULL burn
        // amount (nothing was receipt-backed) at the on-demand id.
        bytes32 sig = ST0xOrchestrator.BurnShortfallMinted.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 shortfallCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(orchestrator) && logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                shortfallCount++;
                (uint256 shortfallAmount, uint256 shortfallId) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(shortfallAmount, amount, "shortfall covers the full burn amount");
                assertEq(shortfallId, onDemandId, "shortfall receipt minted at the on-demand id");
            }
        }
        assertEq(shortfallCount, 1, "exactly one BurnShortfallMinted");
    }

    /// @notice Bootstrap flow: a legacy issuer EOA already holds a real
    /// receipt minted BEFORE the orchestrator exists, so `initialize`
    /// seeds `nextBurnReceiptId = highwaterId + 1` — one past the EOA's
    /// receipt id. The EOA transfers the receipt into the orchestrator
    /// (the ERC-1155 hook accepts it because it comes from the vault's
    /// real receipt contract), the admin repositions the pointer onto it
    /// with `setBurnIndex`, and a subsequent burn consumes it exactly —
    /// no shortfall mint.
    function testProdOrchestratorBootstrapTransferIn() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address eoa = makeAddr("legacyIssuer");

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        address authorizer = address(vault.authorizer());
        // Cached out of the pranked calls below so the pranks target the
        // state-changing calls and not the `receipt()` view.
        IERC1155 receipt = IERC1155(address(vault.receipt()));

        // The EOA mints for itself before the orchestrator exists —
        // receiver gets both the shares and the ERC-1155 receipt.
        pokeRole(authorizer, DEPOSIT, eoa);
        uint256 amount = 4 * TSTOCK;
        uint256 legacyId = vault.highwaterId() + 1;
        vm.prank(eoa);
        vault.mint(amount, eoa, 0, "");
        assertEq(vault.highwaterId(), legacyId, "legacy mint advanced highwater by 1");
        assertEq(receipt.balanceOf(eoa, legacyId), amount, "eoa holds the receipt");

        // Deploy the clone AFTER the legacy mint: the pointer seeds past
        // the legacy id, which is exactly the case `setBurnIndex` exists
        // for.
        (ST0xOrchestrator orchestrator,) = deployClone(owner);
        assertEq(orchestrator.nextBurnReceiptId(), legacyId + 1, "pointer seeded one past the legacy receipt");

        pokeRole(authorizer, DEPOSIT, address(orchestrator));
        pokeRole(authorizer, WITHDRAW, address(orchestrator));
        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        // Documented migration: transfer the receipt in, then point the
        // burn walk at it.
        vm.prank(eoa);
        receipt.safeTransferFrom(eoa, address(orchestrator), legacyId, amount, "");
        assertEq(receipt.balanceOf(address(orchestrator), legacyId), amount, "orchestrator accepted the transfer-in");

        vm.prank(owner);
        orchestrator.setBurnIndex(legacyId);

        // MM burns the EOA's shares against the transferred-in receipt.
        vm.prank(eoa);
        IERC20(address(vault)).approve(address(orchestrator), amount);

        uint256 supplyBefore = IERC20(address(vault)).totalSupply();
        vm.recordLogs();
        vm.prank(mm);
        orchestrator.burn(eoa, amount);

        assertEq(IERC20(address(vault)).balanceOf(eoa), 0, "eoa shares consumed");
        assertEq(IERC20(address(vault)).balanceOf(address(orchestrator)), 0, "no shares stranded");
        assertEq(receipt.balanceOf(address(orchestrator), legacyId), 0, "transferred-in receipt fully consumed");
        assertEq(orchestrator.nextBurnReceiptId(), legacyId + 1, "pointer advanced one past the legacy id");
        assertEq(IERC20(address(vault)).totalSupply(), supplyBefore - amount, "burn reduced supply by the full amount");

        // The transferred-in receipt exactly covered the burn — no
        // shortfall mint fired.
        bytes32 sig = ST0xOrchestrator.BurnShortfallMinted.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(orchestrator) && logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                fail();
            }
        }
    }

    /// @notice Without `DEPOSIT` / `WITHDRAW` on the vault's authoriser the
    /// orchestrator cannot mint: the vault's live authoriser rejects the
    /// deposit leg with `Unauthorized`. Guards against a deploy-script
    /// regression that wires the clone but skips the vault-side grants.
    function testProdOrchestratorRevertsWithoutVaultRoles() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address recipient = makeAddr("recipient");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        // No pokeRole calls: the orchestrator holds MINT_BURN_ROLE locally
        // but has no standing with the vault's authoriser. Partial revert
        // match: the `Unauthorized` data field carries the full
        // `DepositStateChange` encoding, which is not worth reproducing.
        vm.prank(mm);
        vm.expectPartialRevert(Unauthorized.selector);
        orchestrator.mint(recipient, 1e18);
    }

    /// @notice With `DEPOSIT` poked but NOT `WITHDRAW`, minting works but the
    /// burn's redeem leg is rejected by the live authoriser with
    /// `Unauthorized`. Guards against a partial deploy-script regression
    /// that wires the deposit side only.
    function testProdOrchestratorBurnRevertsWithoutWithdrawRole() external {
        LibTestProd.createSelectForkBase(vm);
        address owner = makeAddr("owner");
        address mm = makeAddr("mm");
        address recipient = makeAddr("recipient");
        (ST0xOrchestrator orchestrator,) = deployClone(owner);

        OffchainAssetReceiptVault vault = OffchainAssetReceiptVault(payable(LibTokenInvariants.MSTR_RECEIPT_VAULT));
        address authorizer = address(vault.authorizer());
        // DEPOSIT only — the withdraw-side grant is deliberately missing.
        pokeRole(authorizer, DEPOSIT, address(orchestrator));

        vm.prank(owner);
        orchestrator.grantRole(MINT_BURN_ROLE, mm);

        uint256 amount = 1 * TSTOCK;
        vm.prank(mm);
        orchestrator.mint(recipient, amount);
        assertEq(IERC20(address(vault)).balanceOf(recipient), amount, "mint side still works");

        vm.prank(recipient);
        IERC20(address(vault)).approve(address(orchestrator), amount);

        // Partial revert match: the `Unauthorized` data field carries the
        // full withdraw state-change encoding, which is not worth
        // reproducing.
        vm.prank(mm);
        vm.expectPartialRevert(Unauthorized.selector);
        orchestrator.burn(recipient, amount);
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
        // The pointer was seeded at the pre-mint highwater + 1, which is
        // exactly the id our mint created; the full burn drained it and
        // advanced one past — so the pointer sits at (minted id + 1).
        assertEq(orchestrator.nextBurnReceiptId(), vault.highwaterId() + 1, "next pointer one past highwater");
        // And it advanced strictly forwards.
        assertGt(orchestrator.nextBurnReceiptId(), preNextBurn, "pointer advanced");
    }
}
