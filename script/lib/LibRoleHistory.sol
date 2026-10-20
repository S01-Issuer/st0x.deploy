// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title LibRoleHistory
/// @notice Who holds a role on an authoriser, proven from its full event
/// history. `AccessControl` cannot enumerate role members, so `hasRole` only
/// answers for addresses already suspected. A dedicated authoriser exists to
/// make one minter exclusive, which is a claim about every address: the only
/// way to make it is to replay every `RoleGranted` and `RoleRevoked` since the
/// authoriser was created, and to prove it was created where the replay starts.
library LibRoleHistory {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant ROLE_GRANTED_TOPIC = keccak256("RoleGranted(bytes32,address,address)");
    bytes32 internal constant ROLE_REVOKED_TOPIC = keccak256("RoleRevoked(bytes32,address,address)");
    uint256 internal constant WINDOW = 2000;
    uint256 internal constant MIN_WINDOW = 50;

    /// @notice The holders of `role` after replaying `logs` in chain order.
    function holders(Vm.EthGetLogs[] memory unordered, bytes32 role) internal pure returns (address[] memory members) {
        Vm.EthGetLogs[] memory logs = inChainOrder(unordered);
        address[] memory set = new address[](logs.length);
        uint256 n = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length != 4 || logs[i].topics[1] != role) continue;
            address account = address(uint160(uint256(logs[i].topics[2])));
            if (logs[i].topics[0] == ROLE_GRANTED_TOPIC) {
                if (!_contains(set, n, account)) set[n++] = account;
            } else if (logs[i].topics[0] == ROLE_REVOKED_TOPIC) {
                for (uint256 j = 0; j < n; j++) {
                    if (set[j] == account) {
                        set[j] = set[n - 1];
                        n--;
                        break;
                    }
                }
            }
        }
        members = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            members[i] = set[i];
        }
    }

    /// @notice Problems with `holders` of one role: anyone but `minter` and
    /// `safe` holding it, and, when `minterRequired`, `minter` not holding it.
    function exclusivityProblems(
        string memory label,
        address[] memory holders_,
        address minter,
        address safe,
        bool minterRequired
    ) internal pure returns (string memory problems) {
        bool minterHolds = false;
        for (uint256 i = 0; i < holders_.length; i++) {
            if (holders_[i] == minter) {
                minterHolds = true;
            } else if (holders_[i] != safe) {
                problems = string.concat(problems, label, ": unexpected holder ", VM.toString(holders_[i]), "; ");
            }
        }
        if (minterRequired && !minterHolds) {
            problems = string.concat(problems, label, ": minter ", VM.toString(minter), " does not hold it; ");
        }
    }

    /// @notice A copy of `logs` sorted by block number, then log index.
    function inChainOrder(Vm.EthGetLogs[] memory logs) internal pure returns (Vm.EthGetLogs[] memory sorted) {
        sorted = new Vm.EthGetLogs[](logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            sorted[i] = logs[i];
            for (uint256 j = i; j > 0 && _before(sorted[j], sorted[j - 1]); j--) {
                (sorted[j], sorted[j - 1]) = (sorted[j - 1], sorted[j]);
            }
        }
    }

    function _before(Vm.EthGetLogs memory a, Vm.EthGetLogs memory b) private pure returns (bool) {
        return a.blockNumber < b.blockNumber || (a.blockNumber == b.blockNumber && a.logIndex < b.logIndex);
    }

    /// @notice Every log `emitter` emitted from `fromBlock` to `toBlock`, read
    /// in windows of 2000 blocks. A window the RPC refuses is halved, down to
    /// 50 blocks, and retried.
    function readLogs(address emitter, uint256 fromBlock, uint256 toBlock)
        internal
        view
        returns (Vm.EthGetLogs[] memory all)
    {
        uint256 size = WINDOW;
        uint256 start = fromBlock;
        while (start <= toBlock) {
            uint256 end = nextWindow(start, size, toBlock);
            try VM.eth_getLogs(start, end, emitter, new bytes32[](0)) returns (Vm.EthGetLogs[] memory logs) {
                all = _concat(all, logs);
                start = end + 1;
            } catch (bytes memory reason) {
                size = shrink(size, reason);
            }
        }
    }

    /// @notice The inclusive end of a log window, capped at the final block.
    function nextWindow(uint256 start, uint256 size, uint256 toBlock) internal pure returns (uint256) {
        return start + size - 1 > toBlock ? toBlock : start + size - 1;
    }

    /// @notice Halve a refused window, or propagate the RPC failure at the floor.
    function shrink(uint256 size, bytes memory reason) internal pure returns (uint256) {
        if (size <= MIN_WINDOW) {
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
        return size / 2;
    }

    function _contains(address[] memory set, uint256 n, address value) private pure returns (bool) {
        for (uint256 i = 0; i < n; i++) {
            if (set[i] == value) return true;
        }
        return false;
    }

    function _concat(Vm.EthGetLogs[] memory a, Vm.EthGetLogs[] memory b)
        private
        pure
        returns (Vm.EthGetLogs[] memory out)
    {
        out = new Vm.EthGetLogs[](a.length + b.length);
        for (uint256 i = 0; i < a.length; i++) {
            out[i] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            out[a.length + i] = b[i];
        }
    }
}
