export type ShadowCliOptions = {mode: "once" | "status"; requestId: string};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Parse before creating a process or resolving credentials. No caller text is
// included in errors, and the only mutation mode is one explicitly named run.
export function parseShadowOptions(args: readonly string[]): ShadowCliOptions {
  let mode: ShadowCliOptions["mode"] | undefined, requestId: string | undefined;
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === "--once" || arg === "--status") {
      if (mode !== undefined) throw new Error("SHADOW_ARGUMENTS_INVALID");
      mode = arg === "--once" ? "once" : "status";
    } else if (arg === "--request-id") {
      const value = args[++index];
      if (requestId !== undefined || typeof value !== "string" || !uuid.test(value)) throw new Error("SHADOW_ARGUMENTS_INVALID");
      requestId = value.toLowerCase();
    } else throw new Error("SHADOW_ARGUMENTS_INVALID");
  }
  if (!mode || !requestId) throw new Error("SHADOW_ARGUMENTS_INVALID");
  return {mode, requestId};
}
