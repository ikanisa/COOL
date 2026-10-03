// Review helper only: importing a test file records each real registration,
// including loop-generated names, without executing or replacing test bodies.
const registrations: Array<{ name: string; body_sha256: string }> = [];
const registered: Array<{ name: string; body: string }> = [];
Object.defineProperty(Deno, "test", {
  value: (name: string, body: () => unknown) => {
    if (typeof name !== "string" || typeof body !== "function") {
      throw new Error("Expected the unchanged string/function registrations");
    }
    registered.push({ name, body: body.toString() });
  },
});
for (const path of Deno.args) {
  await import(new URL(path, "file://" + Deno.cwd() + "/").href);
}
for (const entry of registered) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(entry.body),
  );
  registrations.push({
    name: entry.name,
    body_sha256: Array.from(new Uint8Array(digest))
      .map((byte) => byte.toString(16).padStart(2, "0")).join(""),
  });
}
console.log(JSON.stringify(registrations, null, 2));
