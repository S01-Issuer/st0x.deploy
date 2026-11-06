// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";

/// @dev History on every chain: onto the Base-history record on Base, onto the genesis record elsewhere.
contract CLineHistoryEverywhereFixture is IStoxScript, IStoxHistoryMigration {
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({
            id: keccak256("test/fixture/declarations/line/CLineHistoryEverywhereFixture.s.sol"),
            onto: chainId == LibSafeInvariants.BASE_CHAIN_ID
                ? keccak256("test/fixture/declarations/line/BLineBaseHistoryFixture.s.sol")
                : keccak256("test/fixture/declarations/line/ALineGenesisFixture.s.sol"),
            history: true
        });
    }

    function executedAt(uint256 chainId) external pure returns (uint256) {
        return 1_800_000_000 + chainId;
    }
}
