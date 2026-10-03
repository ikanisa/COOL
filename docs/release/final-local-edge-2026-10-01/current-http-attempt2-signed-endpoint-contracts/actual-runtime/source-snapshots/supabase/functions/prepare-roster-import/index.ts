import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { createRosterImportHandler } from "./handler.ts";

Deno.serve(createRosterImportHandler({
  authenticate: async (authorization) => {
    const { user } = await requireUser(authorization);
    return { id: user.id };
  },
  rpc: async (name, args) => await serviceClient().rpc(name, args),
  configuration: () => ({
    model: Deno.env.get("OPENAI_ROSTER_MODEL")?.trim() || "gpt-5-mini",
    apiKey: Deno.env.get("OPENAI_API_KEY")?.trim(),
    decoderUrl: Deno.env.get("ROSTER_DECODER_URL")?.trim(),
    decoderSecret: Deno.env.get("ROSTER_DECODER_SECRET"),
    decoderBuildSha256: Deno.env.get("ROSTER_DECODER_BUILD_SHA256"),
  }),
}));
