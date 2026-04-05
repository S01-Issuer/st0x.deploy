// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    LibCorporateAction,
    CorporateActionNode,
    EffectiveTimeInPast,
    ActionAlreadyComplete,
    ActionDoesNotExist,
    UnknownActionType
} from "src/lib/LibCorporateAction.sol";

contract LibCorporateActionHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 actionId) external {
        LibCorporateAction.cancel(actionId);
    }

    function countCompleted() external view returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    function head() external view returns (uint256) {
        return LibCorporateAction.head();
    }

    function tail() external view returns (uint256) {
        return LibCorporateAction.tail();
    }

    function getNode(uint256 actionId) external view returns (CorporateActionNode memory) {
        return LibCorporateAction.getStorage().nodes[actionId];
    }

    function walkCompleted(uint256 startActionId, uint256 mask, uint256 maxResults)
        external
        view
        returns (uint256[] memory)
    {
        return LibCorporateAction.walkCompleted(startActionId, mask, maxResults);
    }

    function walkPending(uint256 mask, uint256 maxResults) external view returns (uint256[] memory) {
        return LibCorporateAction.walkPending(mask, maxResults);
    }
}

contract LibCorporateActionLinkedListTest is Test {
    LibCorporateActionHarness internal lib;

    function setUp() public {
        lib = new LibCorporateActionHarness();
        vm.warp(1000);
    }

    function testScheduleFirstNode() external {
        uint256 id = lib.schedule(1, 2000, "");
        assertEq(id, 1);
        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 1);
    }

    function testScheduleInOrder() external {
        lib.schedule(1, 2000, "");
        lib.schedule(1, 3000, "");
        lib.schedule(1, 4000, "");
        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 3);
        assertEq(lib.getNode(1).next, 2);
        assertEq(lib.getNode(2).prev, 1);
        assertEq(lib.getNode(2).next, 3);
        assertEq(lib.getNode(3).prev, 2);
    }

    function testScheduleOutOfOrder() external {
        lib.schedule(1, 4000, "");
        lib.schedule(1, 2000, "");
        lib.schedule(1, 3000, "");
        assertEq(lib.head(), 2);
        assertEq(lib.tail(), 1);
        assertEq(lib.getNode(2).next, 3);
        assertEq(lib.getNode(3).prev, 2);
        assertEq(lib.getNode(3).next, 1);
        assertEq(lib.getNode(1).prev, 3);
    }

    function testScheduleInPastReverts() external {
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, uint64(500), uint256(1000)));
        lib.schedule(1, 500, "");
    }

    function testCancelMiddle() external {
        lib.schedule(1, 2000, "");
        lib.schedule(1, 3000, "");
        lib.schedule(1, 4000, "");
        lib.cancel(2);
        assertEq(lib.getNode(1).next, 3);
        assertEq(lib.getNode(3).prev, 1);
    }

    function testCancelHead() external {
        lib.schedule(1, 2000, "");
        lib.schedule(1, 3000, "");
        lib.cancel(1);
        assertEq(lib.head(), 2);
        assertEq(lib.getNode(2).prev, 0);
    }

    function testCancelTail() external {
        lib.schedule(1, 2000, "");
        lib.schedule(1, 3000, "");
        lib.cancel(2);
        assertEq(lib.tail(), 1);
        assertEq(lib.getNode(1).next, 0);
    }

    function testCancelOnlyNode() external {
        lib.schedule(1, 2000, "");
        lib.cancel(1);
        assertEq(lib.head(), 0);
        assertEq(lib.tail(), 0);
    }

    function testCancelCompletedReverts() external {
        lib.schedule(1, 1500, "");
        vm.warp(2000);
        vm.expectRevert(abi.encodeWithSelector(ActionAlreadyComplete.selector, 1));
        lib.cancel(1);
    }

    function testCancelNonexistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(ActionDoesNotExist.selector, 99));
        lib.cancel(99);
    }

    function testCountCompleted() external {
        lib.schedule(1, 1500, "");
        lib.schedule(1, 2500, "");
        lib.schedule(1, 3500, "");
        assertEq(lib.countCompleted(), 0);
        vm.warp(2000);
        assertEq(lib.countCompleted(), 1);
        vm.warp(3000);
        assertEq(lib.countCompleted(), 2);
        vm.warp(4000);
        assertEq(lib.countCompleted(), 3);
    }

    function testFuzzInsertionOrdering(uint8 count, uint256 seed) external {
        count = uint8(bound(count, 1, 20));
        for (uint256 i = 0; i < count; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint64 time = uint64(bound(seed, 1001, type(uint64).max));
            lib.schedule(1, time, "");
        }
        uint256 current = lib.head();
        uint64 prevTime = 0;
        uint256 nodeCount = 0;
        while (current != 0) {
            CorporateActionNode memory node = lib.getNode(current);
            assertTrue(node.effectiveTime >= prevTime, "ordering violated");
            prevTime = node.effectiveTime;
            current = node.next;
            nodeCount++;
        }
        assertEq(nodeCount, count);
    }

    function testParametersStored() external {
        bytes memory params = abi.encode(uint256(42));
        lib.schedule(1, 2000, params);
        assertEq(lib.getNode(1).parameters, params);
    }

    /// Fuzz: random cancellations maintain list integrity — forward and
    /// backward walk counts always match and pointers are consistent.
    function testFuzzCancellationIntegrity(uint256 seed) external {
        uint256 count = 5;
        uint64 baseTime = 2000;
        for (uint256 i = 0; i < count; i++) {
            // i is bounded to < 5 so the cast is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            lib.schedule(1, baseTime + uint64(i) * 1000, "");
        }

        // Cancel 2 random nodes.
        seed = uint256(keccak256(abi.encode(seed)));
        uint256 cancel1 = bound(seed, 1, count);
        seed = uint256(keccak256(abi.encode(seed)));
        uint256 cancel2 = bound(seed, 1, count);

        lib.cancel(cancel1);
        if (cancel2 != cancel1) {
            lib.cancel(cancel2);
        }

        // Walk forward, count nodes, verify ordering.
        uint256 forwardCount = 0;
        uint256 current = lib.head();
        uint64 prevTime = 0;
        uint256 lastSeen = 0;
        while (current != 0) {
            CorporateActionNode memory node = lib.getNode(current);
            assertTrue(node.effectiveTime >= prevTime, "ordering violated after cancel");
            prevTime = node.effectiveTime;
            lastSeen = current;
            current = node.next;
            forwardCount++;
        }

        // Tail should be the last node we saw walking forward.
        if (forwardCount > 0) {
            assertEq(lib.tail(), lastSeen, "tail mismatch after cancellation");
        }

        // Walk backward from tail, count must match.
        uint256 backwardCount = 0;
        current = lib.tail();
        while (current != 0) {
            CorporateActionNode memory node = lib.getNode(current);
            current = node.prev;
            backwardCount++;
        }
        assertEq(forwardCount, backwardCount, "forward/backward count mismatch");
    }
}

contract LibCorporateActionZeroTypeTest is Test {
    LibCorporateActionHarness internal lib;

    function setUp() public {
        lib = new LibCorporateActionHarness();
        vm.warp(1000);
    }

    /// Scheduling with action type 0 always reverts.
    function testScheduleZeroTypeReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownActionType.selector, uint256(0)));
        lib.schedule(0, 2000, "");
    }
}

contract LibCorporateActionTraversalTest is Test {
    LibCorporateActionHarness internal lib;

    function setUp() public {
        lib = new LibCorporateActionHarness();
        vm.warp(1000);
    }

    /// walkCompleted returns completed actions matching the mask.
    function testWalkCompletedBasic() external {
        lib.schedule(1, 1500, "");
        lib.schedule(1, 2500, "");
        lib.schedule(1, 3500, "");

        vm.warp(3000);

        uint256[] memory ids = lib.walkCompleted(0, 1, 10);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    /// walkCompleted from a cursor skips earlier actions.
    function testWalkCompletedFromCursor() external {
        lib.schedule(1, 1500, "");
        lib.schedule(1, 2500, "");
        lib.schedule(1, 3500, "");

        vm.warp(4000);

        uint256[] memory ids = lib.walkCompleted(1, 1, 10);
        assertEq(ids.length, 2);
        assertEq(ids[0], 2);
        assertEq(ids[1], 3);
    }

    /// walkCompleted with non-matching mask returns empty.
    function testWalkCompletedNoMatch() external {
        lib.schedule(1, 1500, "");
        vm.warp(2000);

        uint256 otherType = 1 << 1;
        uint256[] memory ids = lib.walkCompleted(0, otherType, 10);
        assertEq(ids.length, 0);
    }

    /// walkCompleted respects maxResults.
    function testWalkCompletedMaxResults() external {
        lib.schedule(1, 1500, "");
        lib.schedule(1, 2500, "");
        lib.schedule(1, 3500, "");

        vm.warp(4000);

        uint256[] memory ids = lib.walkCompleted(0, 1, 2);
        assertEq(ids.length, 2);
    }

    /// walkPending returns future actions.
    function testWalkPendingBasic() external {
        lib.schedule(1, 1500, "");
        lib.schedule(1, 2500, "");
        lib.schedule(1, 3500, "");

        vm.warp(2000);

        uint256[] memory ids = lib.walkPending(1, 10);
        assertEq(ids.length, 2);
        assertEq(ids[0], 3);
        assertEq(ids[1], 2);
    }

    /// walkPending returns empty when all actions are completed.
    function testWalkPendingAllCompleted() external {
        lib.schedule(1, 1500, "");
        vm.warp(2000);

        uint256[] memory ids = lib.walkPending(1, 10);
        assertEq(ids.length, 0);
    }

    /// countCompleted increments as time passes actions.
    function testCompletedActionCountOverTime() external {
        lib.schedule(1, 1500, "");
        lib.schedule(1, 2500, "");

        assertEq(lib.countCompleted(), 0);
        vm.warp(2000);
        assertEq(lib.countCompleted(), 1);
        vm.warp(3000);
        assertEq(lib.countCompleted(), 2);
    }
}
