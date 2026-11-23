// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH

//! `isin-oracle <op> <0x hex bytes>` prints the ABI encoded answer of the
//! `isin` crate named by `op` as 0x hex.

use isin::checksum::checksum_table;
use std::env;

fn hex_bytes(hex: &str) -> Vec<u8> {
    let digits = hex.strip_prefix("0x").expect("bytes arg must be 0x hex");
    assert!(digits.len().is_multiple_of(2), "bytes arg must be whole bytes");
    (0..digits.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&digits[i..i + 2], 16).expect("bytes arg must be hex"))
        .collect()
}

fn word(n: usize) -> String {
    format!("{n:064x}")
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let value = hex_bytes(&args[1]);
    let encoded = match args[0].as_str() {
        // Strict `parse` (`parse_loose` uppercases and trims); non-UTF-8 bytes are no `&str`.
        "valid" => word(usize::from(
            std::str::from_utf8(&value).is_ok_and(|s| isin::parse(s).is_ok()),
        )),
        "check-digit" => word(usize::from(b'0' + checksum_table(&value))),
        op => panic!("unknown op {op}"),
    };
    println!("0x{encoded}");
}
