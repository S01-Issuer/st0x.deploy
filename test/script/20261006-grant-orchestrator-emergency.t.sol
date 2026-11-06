// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    GrantOrchestratorEmergency,
    NoOrchestratorEmergencyOnChain,
    OrchestratorEmergencyRecordedByBackfill
} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {BackfilledHistoryScriptTest} from "../lib/HistoryMigrationScriptTest.sol";

contract GrantOrchestratorEmergencyTest is BackfilledHistoryScriptTest {
    function newHistoryScript() internal override returns (address) {
        return address(new GrantOrchestratorEmergency());
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.ORCHESTRATOR_EMERGENCY;
    }

    function declaredOnto(uint256) internal pure override returns (bytes32) {
        return LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES;
    }

    function declaredHistory(uint256) internal pure override returns (bool) {
        return true;
    }

    function ranOn(uint256 chainId) internal pure override returns (bool) {
        return onDeploymentChain(chainId);
    }

    function executedAtRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(NoOrchestratorEmergencyOnChain.selector, chainId);
    }

    function runRefusal(uint256 chainId) internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(OrchestratorEmergencyRecordedByBackfill.selector, chainId);
    }

    function assertGrantedAt(string memory network, uint256 chainId, uint256 blockNumber) internal {
        // A fork at the grant's block reads its header and logs; no state at
        // that block is touched, so no archive node is needed.
        vm.createSelectFork(network, blockNumber);
        assertEq(block.chainid, chainId, network);

        bytes32[] memory topics = new bytes32[](3);
        topics[0] = keccak256("RoleGranted(bytes32,address,address)");
        topics[1] = keccak256("EMERGENCY");
        topics[2] = bytes32(uint256(uint160(LibSafeInvariants.safeForChainId(chainId))));
        Vm.EthGetLogs[] memory logs =
            vm.eth_getLogs(blockNumber, blockNumber, LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, topics);
        assertEq(logs.length, 1, string.concat(network, ": emergency grants to the Safe in the block"));
        assertEq(
            GrantOrchestratorEmergency(sHistoryScript).executedAt(chainId),
            block.timestamp,
            string.concat(network, ": executedAt")
        );
    }

    function testExecutedAtIsTheGrantBlockOnEveryChain() external {
        assertGrantedAt(LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID, 52907834);
        assertGrantedAt(LibRainDeploy.ETHEREUM, LibSafeInvariants.ETHEREUM_CHAIN_ID, 26242605);
        assertGrantedAt(LibRainDeploy.HYPEREVM, LibSafeInvariants.HYPEREVM_CHAIN_ID, 49155126);
        assertGrantedAt(LibRainDeploy.ROBINHOOD, LibSafeInvariants.ROBINHOOD_CHAIN_ID, 94480094);
        assertGrantedAt(LibRainDeploy.BSC, LibSafeInvariants.BSC_CHAIN_ID, 128982736);
    }
}
