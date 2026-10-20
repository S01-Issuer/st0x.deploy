// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

/// @title GenerateMetadata
/// @notice sft-ops `generate-metadata`: writes `launch/metadata/<ticker>.json`
/// from Yahoo Finance, with the ISIN from EODHD when `EODHD_API_KEY` is set,
/// through `launch/ffi/generate-metadata.mjs`. Needs `--ffi`.
///
/// `forge script script/GenerateMetadata.s.sol --ffi --sig 'run(string,string,string)' HOOD equity US7707001027`
///
/// An empty type is detected from Yahoo; an empty ISIN is looked up.
contract GenerateMetadata is Script {
    function run(string memory ticker, string memory assetType, string memory isin) external {
        string[] memory cmd = new string[](8);
        cmd[0] = "node";
        cmd[1] = "launch/ffi/generate-metadata.mjs";
        cmd[2] = "--ticker";
        cmd[3] = ticker;
        cmd[4] = "--type";
        cmd[5] = assetType;
        cmd[6] = "--isin";
        cmd[7] = isin;
        console2.log("Metadata written to", string(vm.ffi(cmd)));
    }
}
