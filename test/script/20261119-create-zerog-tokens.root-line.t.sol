// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibSafe} from "rain-deploy-0.1.38/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {ICloneableV2} from "rain-factory-0.2.18/src/interface/ICloneableV2.sol";
import {
    OffchainAssetReceiptVault,
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.2.25/src/abstract/OffchainAssetReceiptVault.sol";
import {DEPOSIT, WITHDRAW} from "rain-vats-0.2.25/src/abstract/OffchainAssetReceiptVault.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.2.25/src/abstract/ReceiptVault.sol";
import {DEPOSIT_ADMIN} from "rain-vats-0.2.25/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {IReceiptV3} from "rain-vats-0.2.25/src/interface/IReceiptV3.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.25/src/interface/IReceiptVaultV3.sol";

import {
    ZerogAuthoriserSafeAdmin,
    ZerogDeployersOutOfStep,
    ZerogOrchestratorGranted,
    ZerogTokenRowNotPlaceholder,
    ZerogTokenTableLengthMismatch,
    ZerogTokenMismatch
} from "../../script/20261119-create-zerog-tokens.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {IStoxUnifiedDeployerV1} from "../../src/interface/IStoxUnifiedDeployerV1.sol";
import {
    AuthoriserNotReady,
    EuAuthoriserNotReady,
    ExpectedGrantMissing,
    LibAuthoriserInvariants
} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    BeaconImplementationMismatch,
    BeaconOwnerMismatch,
    LibBeaconInvariants
} from "../../src/lib/LibBeaconInvariants.sol";
import {ClosureCodehashMismatch, ClosureNotDeployed} from "../../src/lib/LibClosureInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";
import {ZerogTokenCreationFixture} from "./ZerogTokenCreationFixture.sol";

/// @title CreateZerogTokensRootLineTest
/// @notice The last batch on 0G, with the 0G backfill executed and the first two batches created: the two probes, the
/// last 19 rows each created, authorised and handed to the timelock, then the record, onto the backfill.
contract CreateZerogTokensRootLineTest is ZerogTokenCreationFixture, RootLineRecordScriptTest {
    uint256 internal constant LAST_BATCH_FIRST_ROW = 40;

    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new CreateZerogTokensHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.CREATE_ZEROG_TOKENS;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
    }

    function zerogSafe() internal pure returns (address) {
        return LibSafeInvariants.safeForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function zerogTimelock() internal pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function landBeforeOnto() internal override {
        buildZerog();
    }

    /// @dev The 0G backfill, then the first two batches, which leave the line at the backfill.
    function landOnto() internal override {
        landZerogBackfill();
        CreateZerogTokensHarness earlier = new CreateZerogTokensHarness("root-line-earlier");
        for (uint256 batch = 0; batch < 2; batch++) {
            LibSafeFork.executeBundle(vm, Safe(payable(zerogSafe())), earlier.callAuthorBundle());
        }
    }

    function harness() internal view returns (CreateZerogTokensHarness) {
        return CreateZerogTokensHarness(address(sScript));
    }

    function lastVault() internal view returns (address) {
        return harness().callToken(LibProdTokenConfig.productionTokenConfigs().length - 1).receiptVault;
    }

    function lastUnderlying() internal pure returns (string memory) {
        TokenConfig[] memory rows = LibProdTokenConfig.productionTokenConfigs();
        return rows[rows.length - 1].underlying;
    }

    function testBundleIsTheProbesThenTheLastRowsThenItsRecord() external view {
        TokenConfig[] memory rows = LibProdTokenConfig.productionTokenConfigs();
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 2 + 3 * (rows.length - LAST_BATCH_FIRST_ROW) + 1, "bundle length");
        bytes memory probe = abi.encodeCall(ICloneableV2.initialize, (""));
        assertCall(txs[0], harness().callToken(LAST_BATCH_FIRST_ROW).receiptVault, probe, "vault probe");
        assertCall(txs[1], harness().callToken(LAST_BATCH_FIRST_ROW).wrappedTokenVault, probe, "wrapper probe");
        for (uint256 i = LAST_BATCH_FIRST_ROW; i < rows.length; i++) {
            uint256 at = 2 + 3 * (i - LAST_BATCH_FIRST_ROW);
            address vault = harness().callToken(i).receiptVault;
            assertCall(
                txs[at],
                LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1,
                abi.encodeCall(
                    IStoxUnifiedDeployerV1.newTokenAndWrapperVault,
                    (OffchainAssetReceiptVaultConfigV2({
                            initialAdmin: zerogSafe(),
                            receiptVaultConfig: ReceiptVaultConfigV2({
                                asset: address(0), name: rows[i].name, symbol: rows[i].symbol, receipt: address(0)
                            })
                        }))
                ),
                rows[i].underlying
            );
            address authoriser = rows[i].region == Region.EU
                ? LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
                : LibAuthoriserInvariants.authoriserForChainId(block.chainid);
            assertCall(
                txs[at + 1],
                vault,
                abi.encodeCall(OffchainAssetReceiptVault.setAuthorizer, (IAuthorizeV1(authoriser))),
                rows[i].underlying
            );
            assertCall(
                txs[at + 2], vault, abi.encodeCall(Ownable.transferOwnership, (zerogTimelock())), rows[i].underlying
            );
        }
    }

    function assertCall(SafeTx memory entry, address to, bytes memory data, string memory label) internal pure {
        assertEq(entry.to, to, label);
        assertEq(entry.value, 0, label);
        assertEq(entry.data, data, label);
        assertEq(uint8(entry.operation), uint8(0), label);
    }

    function usAuthoriser() internal view returns (address) {
        return LibAuthoriserInvariants.authoriserForChainId(block.chainid);
    }

    function euAuthoriser() internal view returns (address) {
        return LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
    }

    function testPreflightRefusesAMissingUsAuthoriser() external {
        vm.etch(usAuthoriser(), "");
        vm.expectRevert(abi.encodeWithSelector(AuthoriserNotReady.selector, usAuthoriser()));
        sScript.callPreflight();
    }

    function testPreflightRefusesAMissingEuAuthoriser() external {
        vm.etch(euAuthoriser(), "");
        vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotReady.selector, euAuthoriser()));
        sScript.callPreflight();
    }

    function testPreflightRefusesAUsAuthoriserWithoutTheSafesDeposit() external {
        bytes32 deposit = DEPOSIT;
        vm.prank(zerogTimelock());
        IAccessControl(usAuthoriser()).revokeRole(deposit, zerogSafe());
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, usAuthoriser(), deposit, zerogSafe()));
        sScript.callPreflight();
    }

    /// @notice No reviewed step creates the orchestrator on 0G, and whoever first calls the permissionless 0.1.30
    /// deployer picks its admin. So a clone that grants its pinned address `DEPOSIT` or `WITHDRAW` is refused.
    /// @param withdraw Whether the grant is `WITHDRAW` rather than `DEPOSIT`.
    /// @param onEu Whether the grant is on the EU clone rather than the US one.
    function testPreflightRefusesAnAuthoriserThatGrantsTheOrchestrator(bool withdraw, bool onEu) external {
        bytes32 role = withdraw ? WITHDRAW : DEPOSIT;
        address authoriser = onEu ? euAuthoriser() : usAuthoriser();
        vm.prank(zerogTimelock());
        IAccessControl(authoriser).grantRole(role, LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR);
        vm.expectRevert(abi.encodeWithSelector(ZerogOrchestratorGranted.selector, authoriser, role));
        sScript.callPreflight();
    }

    function testPreflightRefusesAnEuAuthoriserWithoutTheMintersDeposit() external {
        bytes32 deposit = DEPOSIT;
        vm.prank(zerogTimelock());
        IAccessControl(euAuthoriser()).revokeRole(deposit, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExpectedGrantMissing.selector, euAuthoriser(), deposit, LibAuthoriserInvariants.GRANTEE_EU_MINTER
            )
        );
        sScript.callPreflight();
    }

    function testPreflightRefusesAnAuthoriserTheSafeStillAdministers() external {
        bytes32 depositAdmin = DEPOSIT_ADMIN;
        vm.prank(zerogTimelock());
        IAccessControl(euAuthoriser()).grantRole(depositAdmin, zerogSafe());
        vm.expectRevert(abi.encodeWithSelector(ZerogAuthoriserSafeAdmin.selector, euAuthoriser(), depositAdmin));
        sScript.callPreflight();
    }

    function testPostStateRefusesARenamedVault() external {
        executeBundle();
        vm.mockCall(lastVault(), abi.encodeCall(IERC20Metadata.name, ()), abi.encode("Another"));
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, lastUnderlying(), "name"));
        sScript.callAssertPostState();
    }

    function testPostStateRefusesARenamedWrapper() external {
        executeBundle();
        address wrapper = harness().callToken(LibProdTokenConfig.productionTokenConfigs().length - 1).wrappedTokenVault;
        vm.mockCall(wrapper, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode("x"));
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, lastUnderlying(), "wrapper symbol"));
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAVaultOffTheTimelock() external {
        executeBundle();
        vm.mockCall(lastVault(), abi.encodeCall(Ownable.owner, ()), abi.encode(zerogSafe()));
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, lastUnderlying(), "owner"));
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAVaultOnAnAuthoriser() external {
        executeBundle();
        vm.mockCall(lastVault(), abi.encodeCall(IAuthorisable.authorizer, ()), abi.encode(address(0xBEEF)));
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, lastUnderlying(), "authoriser"));
        sScript.callAssertPostState();
    }

    /// @notice A 0G table row with any leg already set is refused at that row: the table is filled from these tokens
    /// only after they exist (RAI-4598).
    function testPreflightRefusesATableRowThatIsNotAPlaceholder() external {
        uint256 last = LibTokenInvariants.productionTokensZerog().length - 1;
        uint256[3] memory rowsToSet = [uint256(0), last / 2, last];
        for (uint256 leg = 0; leg < 3; leg++) {
            TokenInstance[] memory table = LibTokenInvariants.productionTokensZerog();
            uint256 row = rowsToSet[leg];
            if (leg == 0) table[row].receipt = address(0xBEEF);
            if (leg == 1) table[row].receiptVault = address(0xBEEF);
            if (leg == 2) table[row].wrappedTokenVault = address(0xBEEF);
            harness().setTable(table);
            vm.expectRevert(abi.encodeWithSelector(ZerogTokenRowNotPlaceholder.selector, row));
            sScript.callPreflight();
        }
    }

    /// @notice A table out of config order, or of another length, is refused: rows pair with the configs by index.
    function testPreflightRefusesATableOutOfConfigOrderOrLength() external {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensZerog();
        string memory first = table[0].underlying;
        table[0].underlying = table[1].underlying;
        table[1].underlying = first;
        harness().setTable(table);
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenRowNotPlaceholder.selector, 0));
        sScript.callPreflight();

        table = LibTokenInvariants.productionTokensZerog();
        TokenInstance[] memory shorter = new TokenInstance[](table.length - 1);
        for (uint256 i = 0; i < shorter.length; i++) {
            shorter[i] = table[i];
        }
        harness().setTable(shorter);
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenTableLengthMismatch.selector, shorter.length, table.length));
        sScript.callPreflight();
    }

    function lastToken() internal view returns (address receipt, address vault, address wrapper) {
        TokenInstance memory created = harness().callToken(LibProdTokenConfig.productionTokenConfigs().length - 1);
        return (created.receipt, created.receiptVault, created.wrappedTokenVault);
    }

    function assertPostStateRefuses(string memory field) internal {
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, lastUnderlying(), field));
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAReceiptOffItsProxy() external {
        executeBundle();
        (address receipt,,) = lastToken();
        vm.etch(receipt, hex"00");
        assertPostStateRefuses("receipt proxy");
    }

    function testPostStateRefusesAVaultOffItsProxy() external {
        executeBundle();
        (, address vault,) = lastToken();
        vm.etch(vault, hex"00");
        assertPostStateRefuses("vault proxy");
    }

    function testPostStateRefusesAWrapperOffItsProxy() external {
        executeBundle();
        (,, address wrapper) = lastToken();
        vm.etch(wrapper, hex"00");
        assertPostStateRefuses("wrapper proxy");
    }

    function testPostStateRefusesAVaultOnAnotherReceipt() external {
        executeBundle();
        (, address vault,) = lastToken();
        vm.mockCall(vault, abi.encodeCall(IReceiptVaultV3.receipt, ()), abi.encode(address(0xBEEF)));
        assertPostStateRefuses("vault receipt");
    }

    function testPostStateRefusesAReceiptManagedByAnother() external {
        executeBundle();
        (address receipt,,) = lastToken();
        vm.mockCall(receipt, abi.encodeCall(IReceiptV3.manager, ()), abi.encode(address(0xBEEF)));
        assertPostStateRefuses("receipt manager");
    }

    function testPostStateRefusesAWrapperOfAnotherAsset() external {
        executeBundle();
        (,, address wrapper) = lastToken();
        vm.mockCall(wrapper, abi.encodeCall(IERC4626.asset, ()), abi.encode(address(0xBEEF)));
        assertPostStateRefuses("wrapper asset");
    }

    function testPostStateRefusesAResymbolledVault() external {
        executeBundle();
        (, address vault,) = lastToken();
        vm.mockCall(vault, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode("x"));
        assertPostStateRefuses("symbol");
    }

    function testPostStateRefusesAMintedWrapper() external {
        executeBundle();
        (,, address wrapper) = lastToken();
        vm.mockCall(wrapper, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(uint256(1)));
        assertPostStateRefuses("wrapper supply");
    }

    function testPostStateRefusesAMintedVault() external {
        executeBundle();
        vm.mockCall(lastVault(), abi.encodeCall(IERC20.totalSupply, ()), abi.encode(uint256(1)));
        vm.expectRevert(abi.encodeWithSelector(ZerogTokenMismatch.selector, lastUnderlying(), "vault supply"));
        sScript.callAssertPostState();
    }

    function testPreflightRefusesABeaconOffTheTimelock() external {
        address beacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        vm.prank(zerogTimelock());
        Ownable(beacon).transferOwnership(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerMismatch.selector, beacon, zerogTimelock(), address(0xBEEF)));
        sScript.callPreflight();
    }

    function assertPreflightRefusesForeignCodeAt(address pinned, bytes32 codehash) internal {
        vm.etch(pinned, hex"00");
        vm.expectRevert(abi.encodeWithSelector(ClosureCodehashMismatch.selector, pinned, codehash, keccak256(hex"00")));
        sScript.callPreflight();
    }

    function testPreflightRefusesAnUnpinnedUnifiedDeployer() external {
        assertPreflightRefusesForeignCodeAt(
            LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_CODEHASH_0_1_1
        );
    }

    function testPreflightRefusesAnUnpinnedVaultDeployer() external {
        assertPreflightRefusesForeignCodeAt(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1
        );
    }

    function testPreflightRefusesAnUnpinnedWrapperDeployer() external {
        assertPreflightRefusesForeignCodeAt(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH_0_1_1
        );
    }

    /// @notice The 0.1.30 vault's `fallback()` delegatecalls the facet, so a facet with no code is refused.
    function testPreflightRefusesAnEmptyFacet() external {
        vm.etch(LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30, "");
        vm.expectRevert(
            abi.encodeWithSelector(ClosureNotDeployed.selector, LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30)
        );
        sScript.callPreflight();
    }

    /// @notice A token beacon that moved to the timelock but still serves its 0.1.1 implementation is refused.
    function testPreflightRefusesAVaultBeaconOffItsImplementation() external {
        address beacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        vm.prank(zerogTimelock());
        (bool ok,) =
            beacon.call(abi.encodeWithSignature("upgradeTo(address)", LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1));
        assertTrue(ok, "beacon moved back");
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconImplementationMismatch.selector,
                beacon,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1
            )
        );
        sScript.callPreflight();
    }

    /// @notice With the vault deployer below its first token nonce, the count refuses typed rather than underflowing.
    function testPreflightRefusesAVaultDeployerBelowItsFirstNonce() external {
        vm.setNonceUnsafe(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1, 2);
        uint256 wrapperNonce = vm.getNonce(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        vm.expectRevert(abi.encodeWithSelector(ZerogDeployersOutOfStep.selector, uint256(2), wrapperNonce));
        sScript.callPreflight();
    }

    function testPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(zerogSafe(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                zerogSafe(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }

    function testArtifactNamesTheBundleForItsSigners() external {
        harness().run();
        assertEq(
            vm.parseJsonString(vm.readFile(harness().callArtifactPath()), ".meta.name"),
            "ST0x: create the 0G production tokens through the audited 0.1.1 unified deployer"
        );
    }
}
