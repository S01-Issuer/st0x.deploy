// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibTotalSupply} from "src/lib/LibTotalSupply.sol";
import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {ERC20_STORAGE_LOCATION} from "src/lib/LibERC20Storage.sol";

contract LibTotalSupplyHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function effectiveTotalSupply() external view returns (uint256) {
        return LibTotalSupply.effectiveTotalSupply();
    }

    function fold() external {
        LibTotalSupply.fold();
    }

    function onAccountMigrated(uint256 fromCursor, uint256 storedBalance, uint256 toCursor, uint256 newBalance)
        external
    {
        LibTotalSupply.onAccountMigrated(fromCursor, storedBalance, toCursor, newBalance);
    }

    function onMint(uint256 amount) external {
        LibTotalSupply.onMint(amount);
    }

    function onBurn(uint256 amount) external {
        LibTotalSupply.onBurn(amount);
    }

    /// @dev Test-only helper: write directly to OZ's `_totalSupply` slot to
    /// seed the harness with a starting totalSupply. `LibERC20Storage` no
    /// longer exposes a setter (production code must not write this slot —
    /// `LibTotalSupply` per-cursor pots own the effective supply), so we do
    /// the slot write inline here.
    function setOzTotalSupply(uint256 supply) external {
        // Bind to a local — inline assembly only accepts literal number
        // constants, and `ERC20_STORAGE_LOCATION` is now derived in-source.
        bytes32 slot = ERC20_STORAGE_LOCATION;
        assembly ("memory-safe") {
            sstore(add(slot, 2), supply)
        }
    }

    function unmigrated(uint256 cursor) external view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.unmigrated[cursor];
    }

    function totalSupplyLatestCursor() external view returns (uint256) {
        LibCorporateAction.CorporateActionStorage storage s = LibCorporateAction.getStorage();
        return s.totalSupplyLatestCursor;
    }
}
