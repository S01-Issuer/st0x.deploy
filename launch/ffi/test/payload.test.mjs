import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "fs";
import { deflatePayload, generateSchemaFromMetadata } from "../rain-meta.mjs";

const root = new URL("../../../", import.meta.url);
const published = JSON.parse(
  readFileSync(
    new URL("test/fixtures/launch/published-documents.json", root),
    "utf-8",
  ),
);

/** The payload bytes of a document's schema item: after the 8-byte magic and
 * the `a4 00` map and key heads, a CBOR byte-string head then the payload. */
function payloadOf(documentHex) {
  const doc = Buffer.from(documentHex.slice(2), "hex");
  const info = doc[10] & 0x1f;
  const size = info < 24 ? 0 : 2 ** (info - 24);
  const length = info < 24 ? info : doc.readUIntBE(11, size);
  const start = 11 + size;
  return doc.subarray(start, start + length);
}

describe("payloads match the documents sft-ops published", () => {
  for (const token of published) {
    const metadata = JSON.parse(
      readFileSync(new URL(token.metadataFile, root), "utf-8"),
    );

    it(`${token.symbol} metadata`, () => {
      assert.deepEqual(
        Buffer.from(deflatePayload(metadata)),
        payloadOf(token.metadataDocument),
      );
    });

    it(`${token.symbol} schema`, () => {
      const schema = generateSchemaFromMetadata(metadata, token.tokenName);
      assert.deepEqual(
        Buffer.from(deflatePayload(schema)),
        payloadOf(token.schemaDocument),
      );
    });
  }
});
