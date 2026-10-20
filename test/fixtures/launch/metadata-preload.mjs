import assert from "node:assert/strict";
import { register } from "node:module";

register(new URL("./metadata-loader.mjs", import.meta.url), import.meta.url);
globalThis.fetch = async (url) => {
  const request = new URL(url);
  assert.equal(request.origin, "https://eodhd.com");
  assert.equal(request.pathname, "/api/search/RAI3577FFITEST");
  assert.equal(request.searchParams.get("api_token"), "launch-test");
  return new Response(
    JSON.stringify([
      {
        Code: "RAI3577FFITEST",
        Exchange: "US",
        ISIN: "US0000000001",
      },
    ]),
    { status: 200 },
  );
};
