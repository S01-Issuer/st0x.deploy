// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";

import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title HistoryMigrationScriptTest
/// @notice A history migration declares `id` onto its predecessor, and
/// `executedAt` refuses every chain it did not run on.
abstract contract HistoryMigrationScriptTest is Test {
    address internal sHistoryScript;

    function newHistoryScript() internal virtual returns (address);

    function declaredId() internal pure virtual returns (bytes32);

    function declaredOnto(uint256 chainId) internal pure virtual returns (bytes32);

    function declaredHistory(uint256 chainId) internal pure virtual returns (bool);

    function ranOn(uint256 chainId) internal pure virtual returns (bool);

    function executedAtRefusal(uint256 chainId) internal pure virtual returns (bytes memory);

    function setUp() public virtual {
        sHistoryScript = newHistoryScript();
        vm.makePersistent(sHistoryScript);
    }

    /// @dev The networks the history migrations ran on: every deployment
    /// network before 0G. 0G ran none of them, so it has no moment for any,
    /// and the backfill records each there record-only
    /// (`LibStoxMigrations.withoutHistory`).
    function historyNetworks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.networksBeforeZerog());
    }

    function ranHistoryOn(uint256 chainId) internal pure returns (bool) {
        SupportedNetwork[] memory networks = historyNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == chainId) return true;
        }
        return false;
    }

    function assertDeclaration(uint256 chainId) internal view {
        ScriptDeclaration memory declared = IStoxScript(sHistoryScript).declaration(chainId);
        assertEq(declared.id, declaredId(), "id");
        assertEq(declared.onto, declaredOnto(chainId), "onto");
        assertEq(declared.history, declaredHistory(chainId), "history");
    }

    function testDeclarationIsItsHistoryRecord(uint256 chainId) external view {
        assertDeclaration(chainId);
    }

    function testDeclarationIsItsRecordOnZerog() external view {
        assertDeclaration(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function testDeclarationIsItsHistoryRecordOnEveryDeploymentChain() external view {
        SupportedNetwork[] memory networks = historyNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertDeclaration(networks[i].chainId);
        }
    }

    function testExecutedAtRefusesChainsItDidNotRunOn(uint256 chainId) external {
        vm.assume(!ranOn(chainId));
        vm.expectRevert(executedAtRefusal(chainId));
        IStoxHistoryMigration(sHistoryScript).executedAt(chainId);
    }
}
