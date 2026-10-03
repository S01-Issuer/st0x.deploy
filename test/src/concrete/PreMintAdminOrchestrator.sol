// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/AccessControlUpgradeable.sol";

/// @title PreMintAdminOrchestrator
/// @notice The orchestrator's initialisation as it stood before
/// `MINT_ADMIN_ROLE` existed: `DEFAULT_ADMIN_ROLE` to `owner` and nothing
/// else. Only the `Initializable` and `AccessControl` legs are reproduced,
/// and both keep their state in fixed ERC-7201 namespaces, so a proxy
/// initialised against this lands in the same storage a live proxy holds.
/// `ST0xOrchestrator.initializeV2` is the call that reconciles it, and a test
/// that upgraded a proxy already carrying the grant could not tell whether
/// that call did anything.
contract PreMintAdminOrchestrator is Initializable, AccessControlUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /// @notice Grant `DEFAULT_ADMIN_ROLE` to `owner`, as the earlier
    /// implementation did. The vault-logic guard and the EIP-712 leg are
    /// left out: neither touches the role storage this fixture exists to set
    /// up, and the guard would need its mocks in place.
    /// @param owner Address granted `DEFAULT_ADMIN_ROLE`.
    function initialize(address owner) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }
}
