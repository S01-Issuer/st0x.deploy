// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title HandSafeOwnedBaseVaultsToTimelockRootLineTest
/// @notice The hand-over on `network()` at its pinned pre-backfill block, onto
/// the executed V5 backfill, beacon-initial-owner bind and orchestrator admin
/// move bundles.
abstract contract HandSafeOwnedBaseVaultsToTimelockRootLineTest is RootLineRecordScriptTest {
    function network() internal pure virtual returns (string memory);

    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new HandSafeOwnedBaseVaultsToTimelockHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, network());
        LibSafeFork.executeBundle(
            vm, Safe(payable(safeAddress())), new BackfillMigrationRegistryV5Harness("root-line").callAuthorBundle()
        );
        LibTestBeaconInitialOwnerBind.execute(vm, safeAddress(), "root-line");
    }

    function landOnto() internal override {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safeAddress())), new OrchestratorAdminToTimelockHarness("root-line").callAuthorBundle()
        );
    }

    function testPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }
}

/// @title HandSafeOwnedBaseVaultsToTimelockBaseRootLineTest
/// @notice On Base the six Safe-owned vaults move before the record.
contract HandSafeOwnedBaseVaultsToTimelockBaseRootLineTest is HandSafeOwnedBaseVaultsToTimelockRootLineTest {
    function network() internal pure override returns (string memory) {
        return LibRainDeploy.BASE;
    }

    function testBundleIsTheSixTransfersThenTheRecord() external view {
        address[6] memory vaults = [
            LibTokenInvariants.WMT_RECEIPT_VAULT,
            LibTokenInvariants.MC_RECEIPT_VAULT,
            LibTokenInvariants.DIS_RECEIPT_VAULT,
            LibTokenInvariants.IFX_RECEIPT_VAULT,
            LibTokenInvariants.SOI_RECEIPT_VAULT,
            LibTokenInvariants.TPRO_RECEIPT_VAULT
        ];
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, vaults.length + 1, "six transfers then the record");
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(txs[i].to, vaults[i], "transfer target");
            assertEq(txs[i].value, 0, "transfer value");
            assertEq(
                txs[i].data,
                abi.encodeCall(Ownable.transferOwnership, (LibTimelockInvariants.timelockForChainId(block.chainid))),
                "transfer calldata"
            );
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call), "transfer operation");
        }
    }
}

/// @title HandSafeOwnedBaseVaultsToTimelockEthereumRootLineTest
/// @notice Off Base the bundle is the record alone.
contract HandSafeOwnedBaseVaultsToTimelockEthereumRootLineTest is HandSafeOwnedBaseVaultsToTimelockRootLineTest {
    function network() internal pure override returns (string memory) {
        return LibStoxDeployNetworks.ETHEREUM;
    }
}
