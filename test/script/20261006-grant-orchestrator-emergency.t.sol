// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    GrantOrchestratorEmergency,
    NoOrchestratorEmergencyOnChain,
    OrchestratorEmergencyRecordedByBackfill
} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";

contract GrantOrchestratorEmergencyTest is Test {
    GrantOrchestratorEmergency internal script;

    function setUp() external {
        script = new GrantOrchestratorEmergency();
        vm.makePersistent(address(script));
    }

    function isGrantChain(uint256 chainId) internal pure returns (bool) {
        return chainId == LibSafeInvariants.BASE_CHAIN_ID || chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID
            || chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID || chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID
            || chainId == LibSafeInvariants.BSC_CHAIN_ID;
    }

    function testDeclarationIsTheEmergencyHistoryRecordOntoTheEuGrant(uint256 chainId) external view {
        ScriptDeclaration memory declared = script.declaration(chainId);
        assertEq(declared.id, LibStoxMigrations.ORCHESTRATOR_EMERGENCY);
        assertEq(declared.onto, LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES);
        assertTrue(declared.history);
    }

    function testExecutedAtRefusesChainsWithoutTheGrant(uint256 chainId) external {
        vm.assume(!isGrantChain(chainId));
        vm.expectRevert(abi.encodeWithSelector(NoOrchestratorEmergencyOnChain.selector, chainId));
        script.executedAt(chainId);
    }

    function testRunRefusesBecauseTheBackfillWritesTheRecord(uint256 chainId) external {
        chainId = bound(chainId, 0, type(uint64).max / 2 - 36);
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorEmergencyRecordedByBackfill.selector, chainId));
        script.run();
    }

    function testRunRefusesOnChainZero() external {
        vm.chainId(0);
        vm.expectRevert(abi.encodeWithSelector(OrchestratorEmergencyRecordedByBackfill.selector, uint256(0)));
        script.run();
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
        assertEq(script.executedAt(chainId), block.timestamp, string.concat(network, ": executedAt"));
    }

    function testExecutedAtIsTheGrantBlockOnEveryChain() external {
        assertGrantedAt(LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID, 52907834);
        assertGrantedAt(LibRainDeploy.ETHEREUM, LibSafeInvariants.ETHEREUM_CHAIN_ID, 26242605);
        assertGrantedAt(LibRainDeploy.HYPEREVM, LibSafeInvariants.HYPEREVM_CHAIN_ID, 49155126);
        assertGrantedAt(LibRainDeploy.ROBINHOOD, LibSafeInvariants.ROBINHOOD_CHAIN_ID, 94480094);
        assertGrantedAt(LibRainDeploy.BSC, LibSafeInvariants.BSC_CHAIN_ID, 128982736);
    }
}
