// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";

contract BuildWeightingBindings is Script {
    string internal constant DIR = "test/composed/";

    uint256 internal constant LEAD_KEY = 0x1EAD;
    uint256 internal constant OPERATOR_KEY_0 = 0x0A00;
    uint256 internal constant POOL_SIZE = 6;
    bytes32 internal constant LEAD_DOMAIN = keccak256("st0x.test.lead-domain");
    bytes32 internal constant POOL_DOMAIN = keccak256("st0x.test.pool-domain");
    string internal constant MAX_DEVIATION = "0.01";
    int256 internal constant MAX_TIME_SPREAD = 600;
    int256 internal constant MIN_PRICE = 100;
    int256 internal constant MAX_PRICE = 1000;
    int256 internal constant MIN_PRICE_VARIANT = 1;

    function line(string memory k, string memory v) internal pure returns (string memory) {
        return string.concat(k, "=", v, "\n");
    }

    function common(address lead, int256 minPrice) internal pure returns (string memory) {
        return string.concat(
            line("st0x-attest-subparser", vm.toString(LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CANDIDATE)),
            line("lead-signer", vm.toString(lead)),
            line("max-time-spread", vm.toString(MAX_TIME_SPREAD)),
            line("min-price", vm.toString(minPrice)),
            line("max-price", vm.toString(MAX_PRICE))
        );
    }

    function mintWeighting(address sixth, int256 minPrice) internal pure returns (string memory) {
        string memory out = common(vm.addr(LEAD_KEY), minPrice);
        for (uint256 i = 0; i < POOL_SIZE; i++) {
            address op = i == POOL_SIZE - 1 && sixth != address(0) ? sixth : vm.addr(OPERATOR_KEY_0 + i);
            out = string.concat(out, line(string.concat("operator-", vm.toString(i + 1)), vm.toString(op)));
        }
        return string.concat(
            out,
            line("lead-domain-separator", vm.toString(LEAD_DOMAIN)),
            line("pool-domain-separator", vm.toString(POOL_DOMAIN)),
            line("max-deviation", MAX_DEVIATION)
        );
    }

    function run() external {
        vm.createDir(DIR, true);
        vm.writeFile(string.concat(DIR, "mint-weighting.bind"), mintWeighting(address(0), MIN_PRICE));
        vm.writeFile(string.concat(DIR, "mint-weighting-operator-6.bind"), mintWeighting(vm.addr(LEAD_KEY), MIN_PRICE));
        vm.writeFile(string.concat(DIR, "mint-weighting-min-price.bind"), mintWeighting(address(0), MIN_PRICE_VARIANT));
        vm.writeFile(string.concat(DIR, "lead-only-mint-weighting.bind"), common(vm.addr(LEAD_KEY), MIN_PRICE));
    }
}
