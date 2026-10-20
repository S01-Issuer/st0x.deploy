// Usage:
//   node launch/ffi/generate-metadata.mjs --ticker <TICKER> [--type etf|equity]
//     [--isin <ISIN>] [--output <path>] [--issuer-name <name>]
//     [--issuer-address <address>] [--offering-framework <framework>]
//
// Writes launch/metadata/<ticker>.json from Yahoo Finance, with the ISIN from
// EODHD when EODHD_API_KEY is set. The output is a starting point: review it
// against docs/LAUNCH.md before opening the metadata PR.
import { writeFileSync } from "fs";
import YahooFinance from "yahoo-finance2";
import { lookupISIN } from "./isin-lookup.mjs";

const DEFAULT_COUNTERPARTIES = [
  { name: "AlpacaDB Inc" },
  {
    name: "Clear Street LLC",
  },
];

const COUNTRY_ISO = {
  "United States": "US",
  Ireland: "IE",
  Luxembourg: "LU",
  "United Kingdom": "GB",
  Canada: "CA",
  Australia: "AU",
  Japan: "JP",
  Germany: "DE",
  France: "FR",
  Switzerland: "CH",
};

const CURRENCY_NAMES = {
  USD: "US Dollar",
  EUR: "Euro",
  GBP: "British Pound",
  CAD: "Canadian Dollar",
  AUD: "Australian Dollar",
  JPY: "Japanese Yen",
  CHF: "Swiss Franc",
};

const CURRENCY_SYMBOLS = {
  USD: "$",
  EUR: "€",
  GBP: "£",
  CAD: "C$",
  AUD: "A$",
  JPY: "¥",
  CHF: "CHF",
};

/** `YYYY-MM-DD` of a Date, or undefined for anything else. */
function isoDate(value) {
  return value instanceof Date ? value.toISOString().split("T")[0] : undefined;
}

function parseArgs(argv) {
  const opts = {
    issuerName: "S1 Issuer",
    issuerAddress: "Kurfürstendamm 15, 10719 Berlin",
    offeringFramework: "Prospectus",
  };
  const names = {
    "--ticker": "ticker",
    "--type": "type",
    "--output": "output",
    "--isin": "isin",
    "--issuer-name": "issuerName",
    "--issuer-address": "issuerAddress",
    "--offering-framework": "offeringFramework",
  };
  for (let i = 0; i < argv.length; i += 2) {
    const key = names[argv[i]];
    if (!key || argv[i + 1] === undefined) {
      throw new Error(`unknown or incomplete option: ${argv[i]}`);
    }
    if (argv[i + 1] !== "") opts[key] = argv[i + 1];
  }
  if (!opts.ticker) throw new Error("--ticker is required");
  return opts;
}

const opts = parseArgs(process.argv.slice(2));
const ticker = opts.ticker.toUpperCase();
const defaultOutput = `launch/metadata/${ticker.toLowerCase()}.json`;
const outputPath = opts.output || defaultOutput;

const yahooFinance = new YahooFinance({ suppressNotices: ["yahooSurvey"] });
const result = await yahooFinance.quoteSummary(ticker, {
  modules: [
    "price",
    "summaryProfile",
    "assetProfile",
    "fundProfile",
    "defaultKeyStatistics",
    "quoteType",
  ],
});
if (!result) throw new Error(`No data found for ticker: ${ticker}`);

const price = result.price;
const profile = result.summaryProfile;
const assetProfile = result.assetProfile;
const fundProfile = result.fundProfile;
const keyStats = result.defaultKeyStatistics;
const quoteType = result.quoteType;

let assetType;
if (opts.type) {
  assetType = opts.type;
} else {
  const yahooType = quoteType?.quoteType?.toUpperCase();
  assetType = yahooType === "ETF" ? "etf" : "equity";
  console.error(
    `  Auto-detected type: ${assetType} (Yahoo quoteType: ${
      yahooType || "unknown"
    })`,
  );
}

const currencyCode = price?.currency ?? "USD";
const profileCountry = profile?.country || assetProfile?.country;
const countryName = profileCountry || "United States";

let isin = "";
if (opts.isin) {
  isin = opts.isin;
} else if (process.env.EODHD_API_KEY) {
  try {
    const found = await lookupISIN(ticker);
    if (found) {
      isin = found;
      console.error(`  ISIN (EODHD): ${isin}`);
    } else {
      console.error(
        `  ISIN not found in EODHD search results for ${ticker}; leaving blank.`,
      );
    }
  } catch (err) {
    console.error(
      `  ISIN lookup failed: ${
        err instanceof Error ? err.message : String(err)
      }. Leaving blank.`,
    );
  }
} else {
  console.error(
    "  ISIN lookup skipped (set EODHD_API_KEY or pass --isin to populate).",
  );
}

const yahooSummary = profile?.longBusinessSummary;
const summary = yahooSummary || assetProfile?.longBusinessSummary || "";

const common = {
  asset_type: assetType === "etf" ? "ETF" : "Equity",
  primary_ticker: ticker,
  code: price?.symbol || ticker,
  name: price?.longName || price?.shortName || ticker,
  exchange: price?.exchangeName || price?.exchange || "",
  description: summary,
  isin,
  tokenised_issuer: {
    name: opts.issuerName,
    address: opts.issuerAddress,
    offering_framework: opts.offeringFramework,
  },
  currency: {
    code: currencyCode,
    name: CURRENCY_NAMES[currencyCode] || currencyCode,
    symbol: CURRENCY_SYMBOLS[currencyCode] || currencyCode,
  },
  country: {
    name: countryName,
    iso: COUNTRY_ISO[countryName] || "",
  },
  offchain_counterparties: DEFAULT_COUNTERPARTIES,
};

const firstTradeDate = quoteType?.firstTradeDateEpochUtc;
const firstTradeDateStr = isoDate(firstTradeDate) ?? "";

let metadata;
if (assetType === "etf") {
  const inceptionDate = keyStats?.fundInceptionDate;
  metadata = {
    ...common,
    category: fundProfile?.categoryName || "",
    inception_date: isoDate(inceptionDate) ?? firstTradeDateStr,
    dividend_paying_frequency: "",
  };
} else {
  metadata = {
    ...common,
    sector: assetProfile?.sector || profile?.sector || "",
    industry: assetProfile?.industry || profile?.industry || "",
    ipo_date: firstTradeDateStr,
  };
}

writeFileSync(outputPath, JSON.stringify(metadata, null, 2) + "\n");
process.stdout.write(outputPath);
