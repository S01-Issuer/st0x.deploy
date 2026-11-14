// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IStoxHistoryMigration, IStoxScript, ScriptDeclaration} from "../../../../src/interface/IStoxScript.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";

error BLineBaseHistoryFixtureNotHistory(uint256 chainId);

/// @dev History onto the genesis record on Base; a record onto the history-everywhere record elsewhere.
contract BLineBaseHistoryFixture is IStoxScript, IStoxHistoryMigration {
    function declaration(uint256 chainId) external pure returns (ScriptDeclaration memory) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return ScriptDeclaration({
                id: keccak256("test/fixture/declarations/line/BLineBaseHistoryFixture.s.sol"),
                onto: keccak256("test/fixture/declarations/line/ALineGenesisFixture.s.sol"),
                history: true
            });
        }
        return ScriptDeclaration({
            id: keccak256("test/fixture/declarations/line/BLineBaseHistoryFixture.s.sol"),
            onto: keccak256("test/fixture/declarations/line/CLineHistoryEverywhereFixture.s.sol"),
            history: false
        });
    }

    function executedAt(uint256 chainId) external pure returns (uint256) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) return 1_700_000_000;
        revert BLineBaseHistoryFixtureNotHistory(chainId);
    }
}
