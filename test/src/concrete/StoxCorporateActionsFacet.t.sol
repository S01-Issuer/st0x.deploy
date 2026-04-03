// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {
    LibCorporateAction,
    CorporateActionNode,
    CORPORATE_ACTION_STORAGE_LOCATION,
    SCHEDULE_CORPORATE_ACTION,
    CANCEL_CORPORATE_ACTION,
    STATUS_SCHEDULED,
    STATUS_COMPLETE,
    EffectiveTimeInPast,
    NotScheduled,
    NodeDoesNotExist
} from "../../../src/lib/LibCorporateAction.sol";

/// @dev Minimal harness that delegates calls to a facet, simulating how the
/// vault would route unknown selectors via its fallback.
contract DelegatecallHarness {
    address public immutable facet;

    constructor(address facet_) {
        facet = facet_;
    }

    fallback() external payable {
        address target = facet;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @dev Thin harness that exposes LibCorporateAction functions directly for
/// unit testing without needing authorization.
contract LibCorporateActionHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes calldata parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 nodeId) external {
        LibCorporateAction.cancel(nodeId);
    }

    function processCompletions() external {
        LibCorporateAction.processCompletions();
    }

    function getNode(uint256 nodeId) external view returns (CorporateActionNode memory) {
        CorporateActionNode storage node = LibCorporateAction.getNode(nodeId);
        return node;
    }

    function globalCAID() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalCAID;
    }

    function head() external view returns (uint256) {
        return LibCorporateAction.getStorage().head;
    }

    function tail() external view returns (uint256) {
        return LibCorporateAction.getStorage().tail;
    }
}

contract StoxCorporateActionsFacetTest is Test {
    StoxCorporateActionsFacet internal facetImpl;
    DelegatecallHarness internal harness;
    ICorporateActionsV1 internal facetViaHarness;

    function setUp() public {
        facetImpl = new StoxCorporateActionsFacet();
        harness = new DelegatecallHarness(address(facetImpl));
        facetViaHarness = ICorporateActionsV1(address(harness));
    }

    /// globalCAID() returns 0 on a fresh deployment.
    function testGlobalCAIDInitiallyZero() external view {
        assertEq(facetViaHarness.globalCAID(), 0);
    }

    /// Facet routing: calling globalCAID() via delegatecall harness works.
    function testFacetRoutingViaDelegatecall() external view {
        uint256 caid = facetViaHarness.globalCAID();
        assertEq(caid, 0);
    }

    /// Storage isolation: two harnesses sharing the same facet have independent storage.
    function testStorageIsolationBetweenHarnesses() external {
        DelegatecallHarness harness2 = new DelegatecallHarness(address(facetImpl));
        ICorporateActionsV1 facet2 = ICorporateActionsV1(address(harness2));

        assertEq(facetViaHarness.globalCAID(), 0);
        assertEq(facet2.globalCAID(), 0);

        bytes32 storageSlot = CORPORATE_ACTION_STORAGE_LOCATION;
        vm.store(address(harness), storageSlot, bytes32(uint256(42)));

        assertEq(facetViaHarness.globalCAID(), 42);
        assertEq(facet2.globalCAID(), 0);
    }

    /// ERC-7201 storage slot matches the documented formula.
    function testStorageSlotCalculation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action.1")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(CORPORATE_ACTION_STORAGE_LOCATION, expected);
    }

    /// Auth permission constants are correct keccak256 hashes.
    function testAuthPermissionConstants() external pure {
        assertEq(SCHEDULE_CORPORATE_ACTION, keccak256("SCHEDULE_CORPORATE_ACTION"));
        assertEq(CANCEL_CORPORATE_ACTION, keccak256("CANCEL_CORPORATE_ACTION"));
    }
}

contract LibCorporateActionLinkedListTest is Test {
    LibCorporateActionHarness internal lib;

    function setUp() public {
        lib = new LibCorporateActionHarness();
        // Start at a reasonable timestamp.
        vm.warp(1000);
    }

    /// Scheduling a single action creates a one-element list.
    function testScheduleSingleAction() external {
        uint256 nodeId = lib.schedule(1, 2000, "");
        assertEq(nodeId, 1);
        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 1);

        CorporateActionNode memory node = lib.getNode(1);
        assertEq(node.actionType, 1);
        assertEq(node.effectiveTime, 2000);
        assertEq(node.status, STATUS_SCHEDULED);
        assertEq(node.monotonicId, 0);
        assertEq(node.prev, 0);
        assertEq(node.next, 0);
    }

    /// Scheduling with effectiveTime in the past reverts.
    function testScheduleInPastReverts() external {
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, 500, 1000));
        lib.schedule(1, 500, "");
    }

    /// Scheduling with effectiveTime == block.timestamp reverts.
    function testScheduleAtCurrentTimeReverts() external {
        vm.expectRevert(abi.encodeWithSelector(EffectiveTimeInPast.selector, 1000, 1000));
        lib.schedule(1, 1000, "");
    }

    /// Insertion at tail (chronological order).
    function testInsertionAtTail() external {
        lib.schedule(1, 2000, "");
        lib.schedule(1, 3000, "");
        lib.schedule(1, 4000, "");

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 3);

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);
        CorporateActionNode memory n3 = lib.getNode(3);

        assertEq(n1.prev, 0);
        assertEq(n1.next, 2);
        assertEq(n2.prev, 1);
        assertEq(n2.next, 3);
        assertEq(n3.prev, 2);
        assertEq(n3.next, 0);
    }

    /// Insertion at head (reverse chronological order).
    function testInsertionAtHead() external {
        lib.schedule(1, 4000, "");
        lib.schedule(1, 3000, "");
        lib.schedule(1, 2000, "");

        assertEq(lib.head(), 3);
        assertEq(lib.tail(), 1);

        // Verify ordering: node3(2000) -> node2(3000) -> node1(4000)
        CorporateActionNode memory n3 = lib.getNode(3);
        CorporateActionNode memory n2 = lib.getNode(2);
        CorporateActionNode memory n1 = lib.getNode(1);

        assertEq(n3.prev, 0);
        assertEq(n3.next, 2);
        assertEq(n2.prev, 3);
        assertEq(n2.next, 1);
        assertEq(n1.prev, 2);
        assertEq(n1.next, 0);
    }

    /// Insertion in the middle.
    function testInsertionInMiddle() external {
        lib.schedule(1, 2000, ""); // node 1
        lib.schedule(1, 4000, ""); // node 2
        lib.schedule(1, 3000, ""); // node 3 — should go between 1 and 2

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 2);

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);
        CorporateActionNode memory n3 = lib.getNode(3);

        // Order: 1(2000) -> 3(3000) -> 2(4000)
        assertEq(n1.next, 3);
        assertEq(n3.prev, 1);
        assertEq(n3.next, 2);
        assertEq(n2.prev, 3);
    }

    /// Same effectiveTime inserts after existing (stable insertion).
    function testSameEffectiveTimeInsertsAfter() external {
        lib.schedule(1, 2000, ""); // node 1
        lib.schedule(1, 2000, ""); // node 2 — same time, goes after

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 2);

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);
        assertEq(n1.next, 2);
        assertEq(n2.prev, 1);
    }

    /// Cancellation of a single-node list empties the list.
    function testCancelSingleNode() external {
        lib.schedule(1, 2000, "");
        lib.cancel(1);

        assertEq(lib.head(), 0);
        assertEq(lib.tail(), 0);

        CorporateActionNode memory n = lib.getNode(1);
        assertEq(n.status, 0);
    }

    /// Cancelling the head updates head pointer.
    function testCancelHead() external {
        lib.schedule(1, 2000, ""); // node 1 (head)
        lib.schedule(1, 3000, ""); // node 2 (tail)

        lib.cancel(1);

        assertEq(lib.head(), 2);
        assertEq(lib.tail(), 2);

        CorporateActionNode memory n2 = lib.getNode(2);
        assertEq(n2.prev, 0);
        assertEq(n2.next, 0);
    }

    /// Cancelling the tail updates tail pointer.
    function testCancelTail() external {
        lib.schedule(1, 2000, ""); // node 1 (head)
        lib.schedule(1, 3000, ""); // node 2 (tail)

        lib.cancel(2);

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 1);

        CorporateActionNode memory n1 = lib.getNode(1);
        assertEq(n1.prev, 0);
        assertEq(n1.next, 0);
    }

    /// Cancelling a middle node updates prev/next pointers.
    function testCancelMiddle() external {
        lib.schedule(1, 2000, ""); // node 1
        lib.schedule(1, 3000, ""); // node 2
        lib.schedule(1, 4000, ""); // node 3

        lib.cancel(2);

        assertEq(lib.head(), 1);
        assertEq(lib.tail(), 3);

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n3 = lib.getNode(3);
        assertEq(n1.next, 3);
        assertEq(n3.prev, 1);
    }

    /// Cannot cancel a completed action.
    function testCannotCancelCompleted() external {
        lib.schedule(1, 1500, "");

        // Advance past effectiveTime and trigger completion.
        vm.warp(2000);
        lib.processCompletions();

        vm.expectRevert(abi.encodeWithSelector(NotScheduled.selector, 1, STATUS_COMPLETE));
        lib.cancel(1);
    }

    /// Cannot cancel an already-cancelled (status=0) action.
    function testCannotCancelAlreadyCancelled() external {
        lib.schedule(1, 2000, "");
        lib.cancel(1);

        vm.expectRevert(abi.encodeWithSelector(NotScheduled.selector, 1, 0));
        lib.cancel(1);
    }

    /// Automatic completion assigns monotonic IDs.
    function testAutomaticCompletion() external {
        lib.schedule(1, 1500, ""); // node 1
        lib.schedule(1, 1800, ""); // node 2

        vm.warp(2000);
        lib.processCompletions();

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);

        assertEq(n1.status, STATUS_COMPLETE);
        assertEq(n1.monotonicId, 1);
        assertEq(n2.status, STATUS_COMPLETE);
        assertEq(n2.monotonicId, 2);
        assertEq(lib.globalCAID(), 2);
    }

    /// Only actions past effectiveTime complete; future ones stay scheduled.
    function testPartialCompletion() external {
        lib.schedule(1, 1500, ""); // node 1
        lib.schedule(1, 3000, ""); // node 2

        vm.warp(2000);
        lib.processCompletions();

        CorporateActionNode memory n1 = lib.getNode(1);
        CorporateActionNode memory n2 = lib.getNode(2);

        assertEq(n1.status, STATUS_COMPLETE);
        assertEq(n1.monotonicId, 1);
        assertEq(n2.status, STATUS_SCHEDULED);
        assertEq(n2.monotonicId, 0);
        assertEq(lib.globalCAID(), 1);
    }

    /// Scheduling triggers processCompletions so stale scheduled actions
    /// auto-complete before the new one is inserted.
    function testScheduleTriggersCompletions() external {
        lib.schedule(1, 1500, ""); // node 1

        vm.warp(2000);
        lib.schedule(1, 3000, ""); // triggers completion of node 1

        CorporateActionNode memory n1 = lib.getNode(1);
        assertEq(n1.status, STATUS_COMPLETE);
        assertEq(n1.monotonicId, 1);
        assertEq(lib.globalCAID(), 1);
    }

    /// Cancel triggers processCompletions, preventing cancellation of actions
    /// whose effectiveTime has passed.
    function testCancelTriggersCompletions() external {
        lib.schedule(1, 1500, ""); // node 1
        lib.schedule(1, 3000, ""); // node 2

        vm.warp(2000);

        // Node 1 should auto-complete when cancel is called, making it uncancellable.
        vm.expectRevert(abi.encodeWithSelector(NotScheduled.selector, 1, STATUS_COMPLETE));
        lib.cancel(1);
    }

    /// Querying a non-existent node reverts.
    function testGetNodeNonExistentReverts() external {
        vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, 0));
        lib.getNode(0);

        vm.expectRevert(abi.encodeWithSelector(NodeDoesNotExist.selector, 1));
        lib.getNode(1);
    }

    /// Parameters are stored and retrievable.
    function testParametersStored() external {
        bytes memory params = abi.encode(uint256(42), uint256(100));
        lib.schedule(1, 2000, params);

        CorporateActionNode memory n = lib.getNode(1);
        assertEq(n.parameters, params);
    }

    /// Fuzz: random insertion sequences always maintain time ordering.
    function testFuzzInsertionOrdering(uint8 count, uint256 seed) external {
        count = uint8(bound(count, 1, 30));

        uint64[] memory times = new uint64[](count);
        for (uint256 i = 0; i < count; i++) {
            // Generate random future times.
            seed = uint256(keccak256(abi.encode(seed, i)));
            times[i] = uint64(bound(seed, 1001, type(uint64).max));
            lib.schedule(1, times[i], "");
        }

        // Walk the list and verify time ordering.
        uint256 current = lib.head();
        uint64 prevTime = 0;
        uint256 nodeCount = 0;
        while (current != 0) {
            CorporateActionNode memory node = lib.getNode(current);
            assertGe(node.effectiveTime, prevTime, "list not time-ordered");
            prevTime = node.effectiveTime;
            current = node.next;
            nodeCount++;
        }
        assertEq(nodeCount, count, "node count mismatch");
    }

    /// Fuzz: random cancellations maintain list integrity.
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

        // Verify list integrity: walk forward, then backward, counts match.
        uint256 forwardCount = 0;
        uint256 current = lib.head();
        uint256 lastSeen = 0;
        while (current != 0) {
            CorporateActionNode memory node = lib.getNode(current);
            assertEq(node.status, STATUS_SCHEDULED, "cancelled node still in list");
            lastSeen = current;
            current = node.next;
            forwardCount++;
        }

        // tail should be the last node we saw walking forward.
        if (forwardCount > 0) {
            assertEq(lib.tail(), lastSeen, "tail mismatch after cancellation");
        }

        // Walk backward from tail.
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
