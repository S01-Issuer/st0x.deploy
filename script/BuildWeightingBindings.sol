// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {WeightingFixture} from "../test/lib/WeightingFixture.sol";

contract BuildWeightingBindings is Script, WeightingFixture {
    string internal constant RAIN_DIR = "src/rain/";

    function binding(string memory key, string memory value) internal pure returns (string memory) {
        return string.concat(key, "=", value);
    }

    function quoted(string memory s) internal pure returns (string memory) {
        return string.concat("\"", s, "\"");
    }

    function common(address lead, int256 minPrice) internal pure returns (string[] memory) {
        string[] memory bindings = new string[](6);
        bindings[0] = binding("st0x-attest-subparser", vm.toString(LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CANDIDATE));
        bindings[1] = binding("lead-signer", vm.toString(lead));
        bindings[2] = binding("lead-source", quoted(LEAD_SOURCE));
        bindings[3] = binding("max-time-spread", vm.toString(MAX_TIME_SPREAD));
        bindings[4] = binding("min-price", vm.toString(minPrice));
        bindings[5] = binding("max-price", vm.toString(MAX_PRICE));
        return bindings;
    }

    function mintWeighting(address sixth, int256 minPrice) internal pure returns (string[] memory) {
        string[] memory head = common(vm.addr(LEAD_KEY), minPrice);
        string[] memory bindings = new string[](head.length + POOL_SIZE + 3);
        for (uint256 i = 0; i < head.length; i++) {
            bindings[i] = head[i];
        }
        for (uint256 i = 0; i < POOL_SIZE; i++) {
            address operator = i == POOL_SIZE - 1 && sixth != address(0) ? sixth : vm.addr(OPERATOR_KEY_0 + i);
            bindings[head.length + i] = binding(string.concat("operator-", vm.toString(i + 1)), vm.toString(operator));
        }
        bindings[head.length + POOL_SIZE] = binding("pool-source-0", quoted(POOL_SOURCE_0));
        bindings[head.length + POOL_SIZE + 1] = binding("pool-source-1", quoted(POOL_SOURCE_1));
        bindings[head.length + POOL_SIZE + 2] = binding("max-deviation", MAX_DEVIATION);
        return bindings;
    }

    /// @notice Writes `<set>.bind` and composes `rain` with those bindings into
    /// `<set>.rl`.
    function build(string memory set, string memory rain, string[] memory bindings) internal {
        string memory bindFile = "";
        string[] memory command = new string[](11 + 2 * bindings.length);
        command[0] = "nix";
        command[1] = "shell";
        command[2] = ".#rain-cli";
        command[3] = "-c";
        command[4] = "rain";
        command[5] = "dotrain";
        command[6] = "compose";
        command[7] = "-i";
        command[8] = string.concat(RAIN_DIR, rain, ".rain");
        command[9] = "-e";
        command[10] = "weighting";
        for (uint256 i = 0; i < bindings.length; i++) {
            bindFile = string.concat(bindFile, bindings[i], "\n");
            command[11 + 2 * i] = "-b";
            command[12 + 2 * i] = bindings[i];
        }
        vm.writeFile(string.concat(DIR, set, ".bind"), bindFile);
        // ffi trims stdout, so the final newline is restored.
        vm.writeFile(string.concat(DIR, set, ".rl"), string.concat(string(vm.ffi(command)), "\n"));
    }

    function run() external {
        vm.createDir(DIR, true);
        build("mint-weighting", "mint-weighting", mintWeighting(address(0), MIN_PRICE));
        build("mint-weighting-operator-6", "mint-weighting", mintWeighting(vm.addr(LEAD_KEY), MIN_PRICE));
        build("mint-weighting-min-price", "mint-weighting", mintWeighting(address(0), MIN_PRICE_VARIANT));
        build("lead-only-mint-weighting", "lead-only-mint-weighting", common(vm.addr(LEAD_KEY), MIN_PRICE));
    }
}
