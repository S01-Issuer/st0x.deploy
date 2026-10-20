/**
 * Look up an ISIN for a ticker through the EODHD search API, the only EODHD
 * endpoint that returns ISINs on the free tier. Returns null when
 * EODHD_API_KEY is unset, when no result matches the ticker exactly, or when
 * the matches carry no ISIN (common for newly launched ETFs). Throws on
 * transport and HTTP errors so the caller decides what to do.
 */
const EODHD_SEARCH_URL = "https://eodhd.com/api/search";

export async function lookupISIN(ticker, options = {}) {
  const apiKey = options.apiKey ?? process.env.EODHD_API_KEY;
  if (!apiKey) return null;

  const fetchImpl = options.fetchImpl ?? fetch;
  const preferredExchange = options.preferredExchange ?? "US";

  const token = encodeURIComponent(apiKey);
  const symbol = encodeURIComponent(ticker);
  const url = `${EODHD_SEARCH_URL}/${symbol}?api_token=${token}&fmt=json`;
  const response = await fetchImpl(url);
  if (!response.ok) {
    throw new Error(
      `EODHD search returned HTTP ${response.status}: ${await response.text()}`,
    );
  }

  return pickISIN(await response.json(), ticker, preferredExchange);
}

/** An exact ticker match on the preferred exchange wins, then any exact match. */
export function pickISIN(results, ticker, preferredExchange) {
  if (!Array.isArray(results) || results.length === 0) return null;
  const target = ticker.toUpperCase();
  const exact = results.filter((r) => r.Code?.toUpperCase() === target);

  const preferred = exact.find(
    (r) => r.Exchange === preferredExchange && r.ISIN,
  );
  if (preferred?.ISIN) return preferred.ISIN;

  const anyMatch = exact.find((r) => r.ISIN);
  return anyMatch?.ISIN ?? null;
}
