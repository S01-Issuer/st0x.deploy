// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";

/// Minimal subclass that transfers ownership to a known address in its
/// constructor so the test can pose as the vault owner without running
/// the full Zoltu-deployer-and-initialize flow. The guard under test is
/// `setAuthorizer`, which only depends on `OwnableUpgradeable`'s owner
/// being set — not on the rest of vault initialization.
contract OwnedStoxReceiptVault is StoxReceiptVault {
    constructor(address owner) {
        _transferOwnership(owner);
    }
}
