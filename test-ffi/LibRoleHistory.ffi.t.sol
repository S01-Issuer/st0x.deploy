// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRoleHistory} from "../script/lib/LibRoleHistory.sol";

contract LibRoleHistoryFfiTest is Test {
    address constant EMITTER = address(0xA11CE);

    function testReadLogsRetriesTheSameStartThenCollectsEveryWindow() external {
        _run("limited");
    }

    function testReadLogsPropagatesTheRpcFailureAtTheWindowFloor() external {
        _run("floor");
    }

    function _run(string memory mode) internal {
        string memory rpc = _fixture("start", mode);
        // The fork backend reads accounts after this call returns, so the
        // fixture stays up on its idle timeout instead of being stopped here.
        this.exercise(rpc, mode);
    }

    function exercise(string memory rpc, string memory mode) external {
        vm.createSelectFork(rpc);
        if (keccak256(bytes(mode)) == keccak256("limited")) {
            Vm.EthGetLogs[] memory logs = this.readLogs{gas: 500000}(100, 1299);
            uint256[6] memory blocks = [uint256(100), 599, 600, 1099, 1100, 1299];
            assertEq(logs.length, blocks.length);
            for (uint256 i = 0; i < blocks.length; i++) {
                assertEq(logs[i].blockNumber, blocks[i]);
                assertEq(logs[i].emitter, EMITTER);
                assertEq(logs[i].data, abi.encode(blocks[i]));
                assertEq(logs[i].topics.length, 1);
                assertEq(logs[i].topics[0], bytes32(uint256(0xBEEF)));
            }
            uint256[2][] memory ranges = new uint256[2][](5);
            ranges[0] = [uint256(100), 1299];
            ranges[1] = [uint256(100), 1099];
            ranges[2] = [uint256(100), 599];
            ranges[3] = [uint256(600), 1099];
            ranges[4] = [uint256(1100), 1299];
            _assertRanges(rpc, ranges);
        } else {
            bytes memory expected;
            try vm.eth_getLogs(100, 130, EMITTER, new bytes32[](0)) returns (Vm.EthGetLogs[] memory) {
                fail("fixture must refuse the control request");
            } catch (bytes memory reason) {
                expected = reason;
            }
            assertGt(expected.length, 0);
            vm.expectRevert(expected);
            this.readLogs{gas: 500000}(100, 2099);
            uint256[2][] memory ranges = new uint256[2][](8);
            ranges[0] = [uint256(100), 130];
            ranges[1] = [uint256(100), 2099];
            ranges[2] = [uint256(100), 1099];
            ranges[3] = [uint256(100), 599];
            ranges[4] = [uint256(100), 349];
            ranges[5] = [uint256(100), 224];
            ranges[6] = [uint256(100), 161];
            ranges[7] = [uint256(100), 130];
            _assertRanges(rpc, ranges);
        }
    }

    function readLogs(uint256 from, uint256 to) external view returns (Vm.EthGetLogs[] memory) {
        return LibRoleHistory.readLogs(EMITTER, from, to);
    }

    function _assertRanges(string memory rpc, uint256[2][] memory ranges) internal {
        string memory stats = _fixture("stats", rpc);
        uint256[][] memory actual = abi.decode(vm.parseJson(stats, ".ranges"), (uint256[][]));
        assertEq(actual.length, ranges.length);
        for (uint256 i = 0; i < ranges.length; i++) {
            assertEq(actual[i][0], ranges[i][0]);
            assertEq(actual[i][1], ranges[i][1]);
        }
    }

    function _fixture(string memory command, string memory argument) internal returns (string memory) {
        string[] memory args = new string[](9);
        args[0] = "env";
        args[1] = "-u";
        args[2] = "NODE_OPTIONS";
        args[3] = "-u";
        args[4] = "EODHD_API_KEY";
        args[5] = "node";
        args[6] = "test/fixtures/launch/role-history-rpc.mjs";
        args[7] = command;
        args[8] = argument;
        return string(vm.ffi(args));
    }
}
