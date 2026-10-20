import assert from "node:assert/strict";

export default class YahooFinance {
  async quoteSummary(ticker) {
    if (ticker === "RAI3577EMPTY") return undefined;
    assert.equal(ticker, "RAI3577FFITEST");
    return {
      price: {
        symbol: ticker,
        longName: "Launch Test Fund",
        currency: "USD",
        exchangeName: "Test Exchange",
      },
      summaryProfile: {
        country: "United States",
        longBusinessSummary: "Test description",
      },
      quoteType: {
        quoteType: "ETF",
        firstTradeDateEpochUtc: new Date("2020-01-02T00:00:00Z"),
      },
      fundProfile: { categoryName: "Test category" },
    };
  }
}
