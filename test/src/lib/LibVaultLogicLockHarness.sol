// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibVaultLogicLock} from "../../../src/lib/LibVaultLogicLock.sol";

contract LibVaultLogicLockHarness {
    function checkToken(address token, address expectedVaultImpl, address expectedReceiptImpl) external view {
        LibVaultLogicLock.checkToken(token, expectedVaultImpl, expectedReceiptImpl);
    }

    function prodBeaconsServe(address expectedVaultImpl, address expectedReceiptImpl) external view returns (bool) {
        return LibVaultLogicLock.prodBeaconsServe(expectedVaultImpl, expectedReceiptImpl);
    }
}
