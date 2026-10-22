// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float} from "rain-math-float-0.3.10/src/lib/LibDecimalFloat.sol";
import {EvaluableV4} from "rainlang-interface-0.2.13/src/interface/IInterpreterCallerV4.sol";

import {
    BootstrapMintCapsOrchestrator,
    MintCapsBootstrapConfig,
    MintCapEntry
} from "../../script/20261011-bootstrap-mint-caps-orchestrator.s.sol";

/// @notice `configure` was given address zero for the minter, which would
/// seat a minter cap on, and grant `MINT_ROLE`/`BURN_ROLE` to, no account.
error HarnessMinterZero();

/// @notice `configure` was given address zero for the recipient, which would
/// seat a recipient cap on no account.
error HarnessRecipientZero();

/// @notice The bootstrap script with a config the test sets: one account
/// that mints and burns, one recipient, one policy for both caps.
contract BootstrapMintCapsOrchestratorHarness is BootstrapMintCapsOrchestrator {
    EvaluableV4 internal sWeighting;
    address internal sMinter;
    address internal sRecipient;
    Float internal sCapacity;
    Float internal sLeakRate;

    function configure(EvaluableV4 memory weighting, address minter, address recipient, Float capacity, Float leakRate)
        external
    {
        if (minter == address(0)) revert HarnessMinterZero();
        if (recipient == address(0)) revert HarnessRecipientZero();
        sWeighting = weighting;
        sMinter = minter;
        sRecipient = recipient;
        sCapacity = capacity;
        sLeakRate = leakRate;
    }

    function bootstrapConfig() internal view override returns (MintCapsBootstrapConfig memory cfg) {
        cfg.weighting = sWeighting;
        cfg.minters = new MintCapEntry[](1);
        cfg.minters[0] = MintCapEntry({account: sMinter, capacity: sCapacity, leakRate: sLeakRate});
        cfg.recipients = new MintCapEntry[](1);
        cfg.recipients[0] = MintCapEntry({account: sRecipient, capacity: sCapacity, leakRate: sLeakRate});
        cfg.burners = new address[](1);
        cfg.burners[0] = sMinter;
    }
}
