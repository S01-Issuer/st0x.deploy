// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";

import {VaultNotOnTimelock} from "../../script/20261103-hand-safe-owned-base-vaults-to-timelock.s.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {
    LibTokenInvariants,
    ReceiptVaultOwnerMismatch,
    TokenInstance,
    TokenTableNotHydrated
} from "../../src/lib/LibTokenInvariants.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {ZerogRootLineScriptTest} from "./ZerogRootLineScriptTest.sol";

/// @title HandSafeOwnedBaseVaultsToTimelockZerogRootLineTest
/// @notice The hand-over on 0G, onto the orchestrator admin move's stand-in record, with the created tokens standing
/// in for 0G's table: the record alone, every 0G vault already on the timelock. On 0G's placeholder table the
/// pre-flight fails closed.
contract HandSafeOwnedBaseVaultsToTimelockZerogRootLineTest is ZerogRootLineScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(zerogHandOver("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK;
    }

    function testZerogHandsNothingOver() external {
        assertEq(
            HandSafeOwnedBaseVaultsToTimelockHarness(address(sScript)).callHandoverVaults().length, 0, "no handover"
        );
        executeBundle();
        LibTokenInvariants.assertUniformOwnership(zerogTokens(), zerogTimelock());
        sScript.callAssertPostState();
    }

    function testZerogPreflightFailsClosedOnThePlaceholderTable() external {
        HandSafeOwnedBaseVaultsToTimelockHarness placeholders =
            new HandSafeOwnedBaseVaultsToTimelockHarness("zerog-root-line-placeholders");
        vm.expectRevert(abi.encodeWithSelector(TokenTableNotHydrated.selector, LibSafeInvariants.ZEROG_CHAIN_ID));
        placeholders.callPreflight();
    }

    function testZerogPreflightRefusesAVaultOffTheTimelock(uint256 index) external {
        TokenInstance[] memory tokens = zerogTokens();
        address vault = tokens[bound(index, 0, tokens.length - 1)].receiptVault;
        vm.prank(zerogTimelock());
        Ownable(vault).transferOwnership(zerogSafe());
        vm.expectRevert(abi.encodeWithSelector(VaultNotOnTimelock.selector, vault, zerogSafe()));
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesAVaultOffTheTimelock() external {
        executeBundle();
        address vault = zerogTokens()[0].receiptVault;
        vm.prank(zerogTimelock());
        Ownable(vault).transferOwnership(zerogSafe());
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, vault, zerogTimelock(), zerogSafe()));
        sScript.callAssertPostState();
    }
}
