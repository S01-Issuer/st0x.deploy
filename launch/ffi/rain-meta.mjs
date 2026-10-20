import { deflate } from "pako";

function titleCase(s) {
  return s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function buildObjectProperties(obj) {
  const props = {};
  for (const [k, v] of Object.entries(obj)) {
    const title = titleCase(k);
    if (typeof v === "string") props[k] = { type: "string", title };
    else if (typeof v === "number") props[k] = { type: "number", title };
    else if (typeof v === "boolean") props[k] = { type: "boolean", title };
    else props[k] = { type: "string", title };
  }
  return props;
}

/**
 * The `{ displayName, schema }` payload sft-ops publishes through
 * `receiptVaultInformation`, derived from the metadata's own keys.
 */
export function generateSchemaFromMetadata(metadata, displayName) {
  const properties = {};

  for (const [key, value] of Object.entries(metadata)) {
    const title = titleCase(key);
    if (typeof value === "string") {
      properties[key] = { type: "string", title };
    } else if (typeof value === "number") {
      properties[key] = { type: "number", title };
    } else if (typeof value === "boolean") {
      properties[key] = { type: "boolean", title };
    } else if (Array.isArray(value)) {
      const itemSchema =
        value.length > 0 && value[0] !== null && typeof value[0] === "object"
          ? { type: "object", properties: buildObjectProperties(value[0]) }
          : { type: "string" };
      properties[key] = { type: "array", title, items: itemSchema };
    } else if (value !== null && typeof value === "object") {
      properties[key] = {
        type: "object",
        title,
        properties: buildObjectProperties(value),
      };
    }
  }

  return { displayName, schema: { type: "object", properties } };
}

/** The deflated `JSON.stringify` bytes that sft-ops `encodeRainMeta` wraps. */
export function deflatePayload(payload) {
  return deflate(new TextEncoder().encode(JSON.stringify(payload)));
}
