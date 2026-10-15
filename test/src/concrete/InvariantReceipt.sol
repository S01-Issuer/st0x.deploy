// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {LibCorporateActionReceipt} from "../../../src/lib/LibCorporateActionReceipt.sol";
import {LibERC1155Storage} from "../../../src/lib/LibERC1155Storage.sol";

/// @dev Receipt harness used by the invariant suite. Initializes `manager`
/// to the invariant vault via direct slot write (bypassing the Receipt
/// base's `initializer` lock — we're in a fresh deployment, not a proxy
/// upgrade path). Exposes the raw stored balance and cursor for
/// assertions.
contract InvariantReceipt is StoxReceipt {
    function testInit(address vaultAddr) external {
        bytes32 slot = 0xe5444a702a2f437387f4eb075af275e349f1dba9a68923d27352f035d01dc200;
        assembly {
            sstore(slot, vaultAddr)
        }
    }

    function rawReceiptBalance(address account, uint256 id) external view returns (uint256) {
        return LibERC1155Storage.underlyingBalance(account, id);
    }

    function holderIdCursor(address account, uint256 id) external view returns (uint256) {
        return LibCorporateActionReceipt.getStorage().accountIdCursor[account][id];
    }
}
