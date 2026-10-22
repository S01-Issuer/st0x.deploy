// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.10/src/lib/LibDecimalFloat.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/interface/ICorporateActionsV1.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {ERC20_STORAGE_LOCATION} from "../../../src/lib/LibERC20Storage.sol";
import {ERC1155_STORAGE_LOCATION} from "../../../src/lib/LibERC1155Storage.sol";
import {InvariantVault} from "./InvariantVault.sol";
import {TestStoxReceipt} from "./TestStoxReceipt.sol";

/// @dev Every share operation on a holder is mirrored on the receipt for each
/// id, so each `(holder, id)` must migrate exactly as `holder` does.
contract ShareAndReceiptMigrationParityTest is Test {
    InvariantVault internal vault;
    TestStoxReceipt internal receipt;

    address[3] internal holders = [address(0xA11CE), address(0xB0B), address(0xCA401)];
    uint256[2] internal ids = [uint256(1), uint256(2)];

    function setUp() public {
        vault = new InvariantVault();
        receipt = new TestStoxReceipt();
        receipt.testInit(address(vault));
        vm.warp(1000);
    }

    function _ratio(int256 numerator, int256 denominator) internal pure returns (Float) {
        return
            LibDecimalFloat.div(
                LibDecimalFloat.packLossless(numerator, 0), LibDecimalFloat.packLossless(denominator, 0)
            );
    }

    function _multiplier(uint256 seed) internal pure returns (Float) {
        uint256 bucket = seed % 6;
        if (bucket == 0) return _ratio(2, 1);
        if (bucket == 1) return _ratio(3, 1);
        if (bucket == 2) return _ratio(1, 1);
        if (bucket == 3) return _ratio(1, 2);
        if (bucket == 4) return _ratio(1, 3);
        return _ratio(3, 2);
    }

    function _schedule(Float multiplier, uint256 delay) internal returns (uint256) {
        return vault.publicSchedule(
            ACTION_TYPE_STOCK_SPLIT_V1, uint64(block.timestamp + delay), LibStockSplit.encodeParametersV1(multiplier)
        );
    }

    function _mint(address to, uint256 amount) internal returns (uint256) {
        vm.recordLogs();
        vault.publicUpdate(address(0), to, amount);
        for (uint256 i = 0; i < ids.length; i++) {
            vm.prank(address(vault));
            receipt.managerMint(address(vault), to, ids[i], amount, "");
        }
        return _assertParity();
    }

    function _burn(address from, uint256 amount) internal returns (uint256) {
        vm.recordLogs();
        vault.publicUpdate(from, address(0), amount);
        for (uint256 i = 0; i < ids.length; i++) {
            vm.prank(address(vault));
            receipt.managerBurn(address(vault), from, ids[i], amount, "");
        }
        return _assertParity();
    }

    function _transfer(address from, address to, uint256 amount) internal returns (uint256) {
        vm.recordLogs();
        vault.publicUpdate(from, to, amount);
        for (uint256 i = 0; i < ids.length; i++) {
            vm.prank(address(vault));
            receipt.managerTransferFrom(address(vault), from, to, ids[i], amount, "");
        }
        return _assertParity();
    }

    function _touch(address holder) internal returns (uint256) {
        return _transfer(holder, holder, 0);
    }

    /// Migrates without a transfer, so the only balance writes are the migration's own.
    function _migrate(address holder) internal returns (uint256) {
        vm.recordLogs();
        vault.publicMigrateAccount(holder);
        for (uint256 i = 0; i < ids.length; i++) {
            receipt.publicMigrateHolderId(holder, ids[i]);
        }
        return _assertParity();
    }

    function _assertParity() internal returns (uint256) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log[] memory shareLogs = new Vm.Log[](logs.length);
        uint256 shareCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(vault) && logs[i].topics[0] == StoxReceiptVault.AccountMigrated.selector) {
                shareLogs[shareCount++] = logs[i];
            }
        }

        for (uint256 j = 0; j < ids.length; j++) {
            uint256 receiptCount = 0;
            for (uint256 i = 0; i < logs.length; i++) {
                if (
                    logs[i].emitter != address(receipt)
                        || logs[i].topics[0] != StoxReceipt.ReceiptAccountMigrated.selector
                        || uint256(logs[i].topics[2]) != ids[j]
                ) {
                    continue;
                }
                assertLt(receiptCount, shareCount, "receipt migrated a pair the shares did not");
                assertEq(logs[i].topics[1], shareLogs[receiptCount].topics[1], "migrated account");
                assertEq(logs[i].data, shareLogs[receiptCount].data, "migration cursors and balances");
                receiptCount++;
            }
            assertEq(receiptCount, shareCount, "migration event count");
        }

        for (uint256 i = 0; i < shareCount; i++) {
            assertTrue(shareLogs[i].topics[1] != bytes32(0), "zero address never migrates");
        }

        for (uint256 h = 0; h < holders.length; h++) {
            for (uint256 j = 0; j < ids.length; j++) {
                assertEq(receipt.holderIdCursor(holders[h], ids[j]), vault.migrationCursor(holders[h]), "cursor");
                assertEq(
                    receipt.rawStoredBalance(holders[h], ids[j]), vault.rawStoredBalance(holders[h]), "stored balance"
                );
                assertEq(receipt.balanceOf(holders[h], ids[j]), vault.balanceOf(holders[h]), "effective balance");
            }
        }
        for (uint256 j = 0; j < ids.length; j++) {
            assertEq(receipt.holderIdCursor(address(0), ids[j]), 0, "receipt zero-address cursor");
        }
        assertEq(vault.migrationCursor(address(0)), 0, "share zero-address cursor");

        return shareCount;
    }

    function testForwardAndReverseSplitsMigrateIdentically(uint64 amountA, uint64 amountB, uint256 m1, uint256 m2)
        external
    {
        _mint(holders[0], uint256(amountA) + 1);
        _mint(holders[1], uint256(amountB) + 1);

        _schedule(_multiplier(m1), 10);
        vm.warp(block.timestamp + 11);
        assertEq(_touch(holders[0]), 1);

        _schedule(_multiplier(m2), 10);
        vm.warp(block.timestamp + 11);
        _transfer(holders[0], holders[1], vault.balanceOf(holders[0]) / 2);
        _burn(holders[1], vault.balanceOf(holders[1]) / 3);
        _touch(holders[0]);
        _touch(holders[1]);
    }

    function testMultiStepGapMigratesIdentically(uint64 amount, uint256 m1, uint256 m2, uint256 m3) external {
        _mint(holders[0], uint256(amount) + 1);
        _mint(holders[1], uint256(amount) + 7);

        _schedule(_multiplier(m1), 10);
        _schedule(_multiplier(m2), 20);
        uint256 last = _schedule(_multiplier(m3), 30);
        vm.warp(block.timestamp + 31);

        assertEq(_touch(holders[0]), 1, "one migration across the whole gap");
        assertEq(vault.migrationCursor(holders[0]), last);
        _transfer(holders[1], holders[2], vault.balanceOf(holders[1]));
    }

    function testCancelledSplitIsSkippedIdentically(uint64 amount, uint256 m1, uint256 m2) external {
        _mint(holders[0], uint256(amount) + 1);

        uint256 cancelled = _schedule(_ratio(2, 1), 10);
        uint256 kept = _schedule(_multiplier(m1), 20);
        _schedule(_multiplier(m2), 30);
        vault.publicCancel(cancelled);
        vm.warp(block.timestamp + 21);

        _touch(holders[0]);
        assertEq(vault.migrationCursor(holders[0]), kept);
        vm.warp(block.timestamp + 10);
        _touch(holders[0]);
    }

    function testMintAndBurnNeverMigrateZeroAddress(uint64 amount, uint256 m1, uint256 m2) external {
        _schedule(_multiplier(m1), 10);
        vm.warp(block.timestamp + 11);
        assertEq(_mint(holders[0], uint256(amount) + 1), 1, "only the recipient migrates on mint");
        _schedule(_multiplier(m2), 10);
        vm.warp(block.timestamp + 11);
        assertEq(_burn(holders[0], vault.balanceOf(holders[0])), 1, "only the sender migrates on burn");
    }

    function testAlreadyCurrentHolderMigrationIsNoOp(uint64 amount, uint256 m) external {
        _mint(holders[0], uint256(amount) + 1);
        _schedule(_multiplier(m), 10);
        vm.warp(block.timestamp + 11);
        assertEq(_touch(holders[0]), 1);
        assertEq(_touch(holders[0]), 0, "already-current holder emits nothing");
        assertEq(_transfer(holders[0], holders[0], vault.balanceOf(holders[0])), 0);
    }

    function testCursorOnlyMigrationEmitsWithoutBalanceWrite(uint64 amount) external {
        _mint(holders[0], uint256(amount) + 1);
        uint256 split = _schedule(_ratio(1, 1), 10);
        vm.warp(block.timestamp + 11);

        address unchanged = holders[0];
        address empty = holders[2];
        uint256 storedBefore = vault.rawStoredBalance(unchanged);

        vm.record();
        assertEq(_migrate(unchanged), 1, "1x split still migrates the funded holder");
        assertEq(_migrate(empty), 1, "any split still migrates the empty holder");
        (, bytes32[] memory shareWrites) = vm.accesses(address(vault));
        (, bytes32[] memory receiptWrites) = vm.accesses(address(receipt));

        assertEq(vault.migrationCursor(unchanged), split);
        assertEq(vault.migrationCursor(empty), split);
        assertEq(vault.rawStoredBalance(unchanged), storedBefore);

        address[2] memory touched = [unchanged, empty];
        for (uint256 h = 0; h < touched.length; h++) {
            bytes32 shareSlot = keccak256(abi.encode(touched[h], ERC20_STORAGE_LOCATION));
            for (uint256 w = 0; w < shareWrites.length; w++) {
                assertTrue(shareWrites[w] != shareSlot, "share balance written");
            }
            for (uint256 j = 0; j < ids.length; j++) {
                bytes32 receiptSlot =
                    keccak256(abi.encode(touched[h], keccak256(abi.encode(ids[j], ERC1155_STORAGE_LOCATION))));
                for (uint256 w = 0; w < receiptWrites.length; w++) {
                    assertTrue(receiptWrites[w] != receiptSlot, "receipt balance written");
                }
            }
        }
    }

    function testRandomSequenceMigratesIdentically(uint256[24] memory ops) external {
        for (uint256 i = 0; i < ops.length; i++) {
            uint256 op = ops[i] % 7;
            uint256 seed = ops[i] / 7;
            address a = holders[seed % holders.length];
            address b = holders[(seed / holders.length) % holders.length];
            uint256 amountSeed = seed / (holders.length * holders.length);

            if (op == 0) {
                _mint(a, amountSeed % 1e24 + 1);
            } else if (op == 1) {
                uint256 balance = vault.balanceOf(a);
                if (balance > 0) _burn(a, amountSeed % balance + 1);
            } else if (op == 2) {
                uint256 balance = vault.balanceOf(a);
                _transfer(a, b, balance == 0 ? 0 : amountSeed % (balance + 1));
            } else if (op == 3) {
                _touch(a);
            } else if (op == 4) {
                _schedule(_multiplier(amountSeed), 1 + amountSeed % 50);
            } else if (op == 5) {
                uint256 length = vault.nodesLength();
                if (length > 1) {
                    // forge-lint: disable-next-line(unchecked-call)
                    try vault.publicCancel(1 + amountSeed % (length - 1)) {} catch {}
                }
            } else {
                vm.warp(block.timestamp + 1 + amountSeed % 60);
            }
        }
        for (uint256 h = 0; h < holders.length; h++) {
            _touch(holders[h]);
        }
    }
}
