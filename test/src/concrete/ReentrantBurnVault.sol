// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IST0xOrchestratorV2} from "../../../src/interface/IST0xOrchestratorV2.sol";

/// @dev Malicious vault logic used to pin `burn`'s reentrancy lock. Served
/// behind a token's registry beacon proxy, it plays the token's ERC-20 shares
/// and redeem legs and, on the FIRST `transferFrom` the orchestrator makes
/// into it, reenters `orchestrator.burn` and records whether that nested call
/// succeeded or what it reverted with. With `nonReentrant` in place the nested
/// call must revert `ReentrancyGuardReentrantCall`; the outer burn then
/// completes normally (the hook swallows the revert and returns true).
contract ReentrantBurnVault {
    IST0xOrchestratorV2 public immutable ORCHESTRATOR;

    /// True once the nested `burn` attempt has been made.
    bool public reentryAttempted;
    /// True iff the nested `burn` call did NOT revert.
    bool public reentrySucceeded;
    /// Raw revert data of the nested `burn` call (empty if it succeeded).
    bytes public reentryRevertData;

    constructor(IST0xOrchestratorV2 orchestrator) {
        ORCHESTRATOR = orchestrator;
    }

    /// ERC-20 leg: `burn` pulls shares from the caller via `transferFrom`.
    /// First call reenters `burn`; later calls (including the one the nested
    /// burn itself makes if the guard is broken) are plain successes.
    function transferFrom(address, address, uint256) external returns (bool) {
        if (!reentryAttempted) {
            reentryAttempted = true;
            try ORCHESTRATOR.burn(address(this), 1, "") {
                reentrySucceeded = true;
            } catch (bytes memory data) {
                reentryRevertData = data;
            }
        }
        return true;
    }

    function highwaterId() external pure returns (uint256) {
        return 1;
    }

    /// Redeem at the 1:1 ratio the orchestrator requires.
    function redeem(uint256 shares, address, address, uint256, bytes calldata) external pure returns (uint256) {
        return shares;
    }
}
