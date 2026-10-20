// Usage:
//   node launch/ffi/payload.mjs <metadata.json> <tokenName> --upload
//   node launch/ffi/payload.mjs <metadata.json> <tokenName> --cid-schema <cid> --cid-meta <cid>
//
// Prints abi.encode(bytes schemaPayload, string schemaCid, bytes metaPayload,
// string metaCid). The payloads are the deflated JSON that LibRainMeta frames;
// the CIDs come from Pinata with --upload, or are given for tests.
import { readFileSync } from "fs";
import { deflatePayload, generateSchemaFromMetadata } from "./rain-meta.mjs";
import { uploadToPinata } from "./pinata.mjs";
import { encodePayloads } from "./abi.mjs";

const [metadataPath, tokenName, ...flags] = process.argv.slice(2);
if (!metadataPath || !tokenName) {
  throw new Error(
    "usage: payload.mjs <metadata.json> <tokenName> (--upload | --cid-schema <cid> --cid-meta <cid>)",
  );
}

function flag(name) {
  const i = flags.indexOf(name);
  return i === -1 ? undefined : flags[i + 1];
}

const metadata = JSON.parse(readFileSync(metadataPath, "utf-8"));
const schema = generateSchemaFromMetadata(metadata, tokenName);

let schemaCid;
let metaCid;
if (flags.includes("--upload")) {
  schemaCid = await uploadToPinata(schema);
  metaCid = await uploadToPinata(metadata);
} else {
  schemaCid = flag("--cid-schema");
  metaCid = flag("--cid-meta");
  if (!schemaCid || !metaCid) {
    throw new Error("pass --upload, or both --cid-schema and --cid-meta");
  }
}

process.stdout.write(
  encodePayloads(
    deflatePayload(schema),
    schemaCid,
    deflatePayload(metadata),
    metaCid,
  ),
);
