import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pickISIN } from "../isin-lookup.mjs";

const make = (over = {}) => ({
  Code: "X",
  Exchange: "US",
  Name: "",
  Type: "Common Stock",
  Country: "USA",
  Currency: "USD",
  ISIN: null,
  isPrimary: false,
  ...over,
});

describe("pickISIN", () => {
  it("returns null for empty results", () => {
    assert.equal(pickISIN([], "AAPL", "US"), null);
  });

  it("prefers an exact ticker match on the preferred exchange with an ISIN", () => {
    const results = [
      make({ Code: "CEG", Exchange: "US", ISIN: "US21037T1097" }),
      make({ Code: "CEG2", Exchange: "LSE", ISIN: "LU1437015735" }),
    ];
    assert.equal(pickISIN(results, "CEG", "US"), "US21037T1097");
  });

  it("falls back to any exact match with an ISIN", () => {
    const results = [
      make({ Code: "TSM", Exchange: "US", ISIN: null }),
      make({ Code: "TSM", Exchange: "MX", ISIN: "US8740391003" }),
    ];
    assert.equal(pickISIN(results, "TSM", "US"), "US8740391003");
  });

  it("returns null when the matches carry no ISIN", () => {
    assert.equal(
      pickISIN(
        [make({ Code: "DRAM", Exchange: "US", ISIN: null })],
        "DRAM",
        "US",
      ),
      null,
    );
  });

  it("matches the ticker case-insensitively", () => {
    assert.equal(
      pickISIN(
        [make({ Code: "tsm", Exchange: "US", ISIN: "US8740391003" })],
        "TSM",
        "US",
      ),
      "US8740391003",
    );
  });

  it("ignores a ticker that only shares a prefix", () => {
    assert.equal(
      pickISIN(
        [make({ Code: "CEG2", Exchange: "LSE", ISIN: "LU1437015735" })],
        "CEG",
        "US",
      ),
      null,
    );
  });
});
