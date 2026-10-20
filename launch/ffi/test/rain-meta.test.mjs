import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "fs";
import { inflate } from "pako";
import { deflatePayload, generateSchemaFromMetadata } from "../rain-meta.mjs";

describe("payloads", () => {
  it("deflates the JSON.stringify bytes of the payload", () => {
    const metadata = JSON.parse(
      readFileSync(
        new URL("../../metadata/dis.json", import.meta.url),
        "utf-8",
      ),
    );
    const text = new TextDecoder().decode(inflate(deflatePayload(metadata)));
    assert.equal(text, JSON.stringify(metadata));
  });

  it("derives the schema from the metadata keys in file order", () => {
    const schema = generateSchemaFromMetadata(
      {
        primary_ticker: "X",
        price: 1,
        listed: true,
        country: { iso: "US" },
        offchain_counterparties: [{ name: "A" }],
      },
      "X ST0x",
    );
    assert.deepEqual(schema, {
      displayName: "X ST0x",
      schema: {
        type: "object",
        properties: {
          primary_ticker: { type: "string", title: "Primary Ticker" },
          price: { type: "number", title: "Price" },
          listed: { type: "boolean", title: "Listed" },
          country: {
            type: "object",
            title: "Country",
            properties: { iso: { type: "string", title: "Iso" } },
          },
          offchain_counterparties: {
            type: "array",
            title: "Offchain Counterparties",
            items: {
              type: "object",
              properties: { name: { type: "string", title: "Name" } },
            },
          },
        },
      },
    });
  });
});
