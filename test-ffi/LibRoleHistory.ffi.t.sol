// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {DEPOSIT} from "rain-vats-0.2.5/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {DEPOSIT_ADMIN} from "rain-vats-0.2.5/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibRoleHistory} from "../script/lib/LibRoleHistory.sol";
import {DedicatedAuthoriserNotExclusive} from "../script/20261020-launch-base-tokens.s.sol";
import {TokenPlan} from "../src/lib/LibLaunchPlan.sol";
import {LaunchBaseTokensHarness} from "../test/script/LaunchBaseTokensHarness.sol";

contract LibRoleHistoryFfiTest is Test {
    address constant EMITTER = address(0xA11CE);

    function testReadLogsRetriesTheSameStartThenCollectsEveryWindow() external {
        _run("limited");
    }

    function testReadLogsPropagatesTheRpcFailureAtTheWindowFloor() external {
        _run("floor");
    }

    /// @notice Both ends of the range are read, including a final window of
    /// one block and a range of one block.
    function testReadLogsIncludesAOneBlockFinalWindow() external {
        this.exerciseEdges(_fixture("start", "limited"));
    }

    function exerciseEdges(string memory rpc) external {
        vm.createSelectFork(rpc);
        Vm.EthGetLogs[] memory logs = this.readLogs{gas: 500000}(100, 1100);
        uint256[5] memory blocks = [uint256(100), 599, 600, 1099, 1100];
        assertEq(logs.length, blocks.length);
        for (uint256 i = 0; i < blocks.length; i++) {
            assertEq(logs[i].blockNumber, blocks[i]);
        }
        logs = this.readLogs{gas: 500000}(1100, 1100);
        assertEq(logs.length, 1);
        assertEq(logs[0].blockNumber, 1100);
    }

    /// @notice The dedicated-authoriser check replays the authoriser's creation
    /// block: a DEPOSIT grant there, and a DEPOSIT_ADMIN grant to anyone but
    /// governance, are refused.
    function testDedicatedAuthoriserCheckReplaysFromTheCreationBlock() external {
        this.exerciseAuthoriser(_fixture("start", "authoriser"));
    }

    function exerciseAuthoriser(string memory rpc) external {
        vm.createSelectFork(rpc);
        vm.roll(200);
        LaunchBaseTokensHarness script = new LaunchBaseTokensHarness();
        vm.etch(EMITTER, hex"00");
        vm.mockCall(EMITTER, abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));
        vm.mockCall(
            EMITTER, abi.encodeWithSelector(IAccessControl.hasRole.selector, DEPOSIT, address(0x5157)), abi.encode(true)
        );
        vm.mockCall(
            EMITTER,
            abi.encodeWithSelector(IAccessControl.hasRole.selector, DEPOSIT_ADMIN, address(0xad31)),
            abi.encode(true)
        );
        TokenPlan memory tokenPlan;
        tokenPlan.landingAuthoriser = EMITTER;
        tokenPlan.dedicated = true;
        tokenPlan.dedicatedMinter = address(0x0958);
        tokenPlan.dedicatedDeployBlock = 100;
        tokenPlan.dedicatedMinterGrantPending = true;
        vm.expectRevert(
            abi.encodeWithSelector(
                DedicatedAuthoriserNotExclusive.selector,
                string.concat(
                    "DEPOSIT: unexpected holder ",
                    vm.toString(address(0x5157)),
                    "; DEPOSIT_ADMIN: unexpected holder ",
                    vm.toString(address(0xad31)),
                    "; "
                )
            )
        );
        script.checkDedicatedAuthoriser(tokenPlan);
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
