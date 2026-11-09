// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IRainlangV2} from "rainlang-0.2.33/src/interface/IRainlangV2.sol";
import {
    EvaluableV4,
    SignedContextV2,
    IParserV2,
    IInterpreterV4,
    IInterpreterStoreV3
} from "rainlang-0.2.33/src/interface/IInterpreterCallerV5.sol";
import {
    DEPLOYED_ADDRESS as RAINLANG_0_1_12,
    BYTECODE_HASH as RAINLANG_0_1_12_CODEHASH
} from "rainlang-deploy-0.1.12/src/generated/0_1_12/Rainlang.sol";
import {
    DEPLOYED_ADDRESS as RAINLANG_COMPILER_0_1_12,
    BYTECODE_HASH as RAINLANG_COMPILER_0_1_12_CODEHASH
} from "rainlang-deploy-0.1.12/src/generated/0_1_12/RainlangCompiler.sol";
import {
    DEPLOYED_ADDRESS as RAINLANG_INTERPRETER_0_1_12,
    BYTECODE_HASH as RAINLANG_INTERPRETER_0_1_12_CODEHASH
} from "rainlang-deploy-0.1.12/src/generated/0_1_12/RainlangInterpreter.sol";
import {
    DEPLOYED_ADDRESS as RAINLANG_STORE_0_1_12,
    BYTECODE_HASH as RAINLANG_STORE_0_1_12_CODEHASH
} from "rainlang-deploy-0.1.12/src/generated/0_1_12/RainlangStore.sol";
import {
    DEPLOYED_ADDRESS as RAINLANG_PARSER_0_1_12,
    BYTECODE_HASH as RAINLANG_PARSER_0_1_12_CODEHASH
} from "rainlang-deploy-0.1.12/src/generated/0_1_12/RainlangParser.sol";

import {ST0xOrchestrator} from "src/concrete/ST0xOrchestrator.sol";
import {LibProdDeployV4} from "src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "test/lib/LibTestDeploy.sol";
import {LibTestOrchestratorDeploy} from "test/lib/LibTestOrchestratorDeploy.sol";
import {MockMintRecipient} from "test/src/concrete/MockMintRecipient.sol";
import {ST0xOrchestratorMintWeightingFixture} from "test/src/concrete/ST0xOrchestratorMintWeightingFixture.sol";
import {
    OBSERVATION_SIGNER,
    OBSERVATION_DOMAIN,
    OBSERVATION_SYMBOL,
    OBSERVATION_PRICE,
    OBSERVATION_TIME,
    ALPACA_SOURCE,
    YAHOO_SOURCE,
    OBSERVATION_CURRENCY,
    OBSERVATION_ROWS,
    ALPACA_SIGNATURE,
    YAHOO_SIGNATURE
} from "test/src/concrete/St0xAttestSubParser.signedPriceObservation.t.sol";

/// @dev The first base block with the Rainlang 0_1_12 deployment.
uint256 constant BASE_FORK_BLOCK = 53420495;
/// @dev `BASE_FORK_BLOCK`'s timestamp.
uint256 constant BASE_FORK_TIMESTAMP = 1793630337;

/// @title ST0xOrchestratorBaseForkFixture
/// @notice Base forked at `BASE_FORK_BLOCK`, minting through the candidate
/// orchestrator, deployed as the registry beacon proxy of its beacon, with
/// weightings parsed and evaluated by the Rainlang deployed on base (nothing
/// etched) using the words of the candidate `St0xAttestSubParser`. The vault
/// side is mocked as in `ST0xOrchestratorMintWeightingFixture`, as `tAAPL`.
/// The attestations are the price API's signed AAPL observations byte for
/// byte, from `St0xAttestSubParser.signedPriceObservation.t.sol`.
abstract contract ST0xOrchestratorBaseForkFixture is ST0xOrchestratorMintWeightingFixture {
    using Strings for address;

    /// @inheritdoc ST0xOrchestratorMintWeightingFixture
    function tokenSymbol() internal pure override returns (string memory) {
        return "tAAPL";
    }

    function setUp() public virtual override {
        vm.createSelectFork(LibRainDeploy.BASE, BASE_FORK_BLOCK);
        assertEq(block.timestamp, BASE_FORK_TIMESTAMP, "fork timestamp");
        _assertBaseRainlang();

        assertEq(
            LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CREATION_CODE_CANDIDATE),
            LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CANDIDATE,
            "subparser address"
        );

        LibTestDeploy.bindBeaconInitialOwner(vm, OWNER);
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, OWNER);
        recipient = new MockMintRecipient(true);
        _makeGuardPass();
        LibTestOrchestratorDeploy.deployBeacon();
        orchestrator = ST0xOrchestrator(payable(LibTestOrchestratorDeploy.deployInstance(vm, makeAddr("deployer"))));

        _mockToken(TOKEN, tokenSymbol());

        bytes32 mintRole = orchestrator.MINT_ROLE();
        vm.prank(OWNER);
        orchestrator.grantRole(mintRole, MINTER);
    }

    function _assertBaseRainlang() internal view {
        assertEq(RAINLANG_0_1_12.codehash, RAINLANG_0_1_12_CODEHASH, "rainlang codehash");
        assertEq(RAINLANG_COMPILER_0_1_12.codehash, RAINLANG_COMPILER_0_1_12_CODEHASH, "compiler codehash");
        assertEq(RAINLANG_INTERPRETER_0_1_12.codehash, RAINLANG_INTERPRETER_0_1_12_CODEHASH, "interpreter codehash");
        assertEq(RAINLANG_STORE_0_1_12.codehash, RAINLANG_STORE_0_1_12_CODEHASH, "store codehash");
        assertEq(RAINLANG_PARSER_0_1_12.codehash, RAINLANG_PARSER_0_1_12_CODEHASH, "parser codehash");
        IRainlangV2 rainlang = IRainlangV2(RAINLANG_0_1_12);
        assertEq(rainlang.compiler(), RAINLANG_COMPILER_0_1_12, "compiler");
        assertEq(rainlang.interpreter(), RAINLANG_INTERPRETER_0_1_12, "interpreter");
        assertEq(rainlang.store(), RAINLANG_STORE_0_1_12, "store");
        assertEq(rainlang.parser(), RAINLANG_PARSER_0_1_12, "parser");
    }

    /// `rainlang`, complete with its own pragma, parsed by the compiler on
    /// base and bound to the interpreter and store on base.
    function _baseEvaluable(string memory rainlang) internal view returns (EvaluableV4 memory) {
        return EvaluableV4({
            interpreter: IInterpreterV4(RAINLANG_INTERPRETER_0_1_12),
            store: IInterpreterStoreV3(RAINLANG_STORE_0_1_12),
            bytecode: IParserV2(RAINLANG_COMPILER_0_1_12).parse2(bytes(rainlang))
        });
    }

    /// The `using-words-from` pragma for the candidate subparser.
    function _baseUsingWords() internal pure returns (string memory) {
        return string.concat("using-words-from ", LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CANDIDATE.toHexString(), "\n");
    }

    function _observation(bytes32 source, bytes memory signature) internal pure returns (SignedContextV2 memory) {
        bytes32[] memory context = new bytes32[](OBSERVATION_ROWS);
        context[0] = OBSERVATION_SYMBOL;
        context[1] = OBSERVATION_PRICE;
        context[2] = OBSERVATION_TIME;
        context[3] = source;
        context[4] = OBSERVATION_CURRENCY;
        return SignedContextV2({
            signer: OBSERVATION_SIGNER, domainSeparator: OBSERVATION_DOMAIN, context: context, signature: signature
        });
    }

    function _alpaca() internal pure returns (SignedContextV2 memory) {
        return _observation(ALPACA_SOURCE, ALPACA_SIGNATURE);
    }

    function _yahoo() internal pure returns (SignedContextV2 memory) {
        return _observation(YAHOO_SOURCE, YAHOO_SIGNATURE);
    }

    /// `observation` as the only attestation, the lead.
    function _asLead(SignedContextV2 memory observation) internal pure returns (SignedContextV2[] memory) {
        SignedContextV2[] memory attestations = new SignedContextV2[](1);
        attestations[0] = observation;
        return attestations;
    }
}
