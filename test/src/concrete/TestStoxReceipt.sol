// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibCorporateActionReceipt} from "../../../src/lib/LibCorporateActionReceipt.sol";
import {LibERC1155Storage} from "../../../src/lib/LibERC1155Storage.sol";

/// @dev Test-only subclass that exposes an `initialize` path bypassing the
/// `initializer` modifier of the real `Receipt`, so tests can directly drive
/// a `StoxReceipt` against our mock. `publicManagerMint` / `publicManagerBurn`
/// go through the vault-as-manager path.
contract TestStoxReceipt is StoxReceipt {
    function testInit(address vaultAddr) external {
        // Bypass ethgild's `initializer` lock by writing the manager slot
        // directly. We're initializing a fresh deployment in-test, so the
        // one-shot initializer guard is irrelevant for our purposes.
        bytes32 slot = 0xe5444a702a2f437387f4eb075af275e349f1dba9a68923d27352f035d01dc200;
        assembly {
            sstore(slot, vaultAddr)
        }
    }

    /// Expose direct storage read so tests can inspect the raw stored
    /// balance (pre-rebase) without going through the `balanceOf` override.
    function rawStoredBalance(address account, uint256 id) external view returns (uint256) {
        return LibERC1155Storage.underlyingBalance(account, id);
    }

    /// Expose the cursor for assertions.
    function holderIdCursor(address account, uint256 id) external view returns (uint256) {
        return LibCorporateActionReceipt.getStorage().accountIdCursor[account][id];
    }

    /// Expose internal migration so tests can exercise the zero-address
    /// short-circuit directly.
    function publicMigrateHolderId(address account, uint256 id) external {
        migrateHolderId(account, id, ICorporateActionsV1(this.manager()));
    }
}
