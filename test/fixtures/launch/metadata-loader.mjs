export async function resolve(specifier, context, nextResolve) {
  if (specifier === "yahoo-finance2") {
    return {
      url: new URL("./yahoo-fixture.mjs", import.meta.url).href,
      shortCircuit: true,
    };
  }
  return nextResolve(specifier, context);
}
