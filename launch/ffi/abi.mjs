function word(n) {
  return BigInt(n).toString(16).padStart(64, "0");
}

function dynamic(bytes) {
  const hex = Buffer.from(bytes).toString("hex");
  const padded = hex.padEnd(Math.ceil(hex.length / 64) * 64, "0");
  return word(bytes.length) + padded;
}

/** `abi.encode(bytes, string, bytes, string)`, as 0x-prefixed hex. */
export function encodePayloads(schemaPayload, schemaCid, metaPayload, metaCid) {
  const tails = [
    schemaPayload,
    Buffer.from(schemaCid, "utf8"),
    metaPayload,
    Buffer.from(metaCid, "utf8"),
  ].map(dynamic);
  let offset = 32 * tails.length;
  let head = "";
  for (const tail of tails) {
    head += word(offset);
    offset += tail.length / 2;
  }
  return `0x${head}${tails.join("")}`;
}
