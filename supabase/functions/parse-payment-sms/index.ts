import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";
import { hashPhone, redactSmsForParser } from "../_shared/hash.ts";
import {
  parserSchemaVersion,
  smsParserJsonSchema,
} from "../_shared/sms_schema.ts";

function extractOutputText(response: any): string {
  if (typeof response.output_text === "string") return response.output_text;
  for (const item of response.output ?? []) {
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }
  return "";
}

function sanitizeParsedJson(parsed: Record<string, unknown>) {
  return {
    ...parsed,
    sender_phone: parsed.sender_phone ? "[hashed]" : null,
    receiver_phone: parsed.receiver_phone ? "[hashed]" : null,
  };
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let rawSmsId: string | null = null;
  try {
    requireInternalRequest(req);
    const { raw_sms_id } = await req.json();
    rawSmsId = raw_sms_id;
    const supabase = serviceClient();
    const { data: rawSms, error: rawError } = await supabase
      .from("raw_payment_sms")
      .select("*")
      .eq("id", raw_sms_id)
      .single();
    if (rawError) throw rawError;

    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
    const redactedBody = redactSmsForParser(rawSms.raw_body);
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requireEnv("OPENAI_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        input: [
          {
            role: "system",
            content:
              "Parse mobile money notification SMS for Collect. Return only facts present in the SMS. Detect a 6-digit Collect ID only when it is explicitly present as a member/user/reference ID. Do not extract payer names, receiver names, payment reasons, or separate contribution/reference codes. Do not rely on separate contribution/reference codes for allocation. Do not infer missing values. Only classify incoming received money as incoming payment. Ignore promotional, loan, airtime, failed, balance-only, and outgoing messages.",
          },
          {
            role: "user",
            content:
              `SMS sender: ${rawSms.raw_sender}\nSMS body:\n${redactedBody}`,
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "collect_sms_payment_event",
            strict: true,
            schema: smsParserJsonSchema,
          },
        },
      }),
    });

    let parsed: Record<string, unknown>;
    const parserModel = model;

    if (!response.ok) {
      await supabase.from("raw_payment_sms").update({
        parse_status: "failed",
      })
        .eq("id", raw_sms_id);
      return jsonResponse({
        error: "OpenAI parse failed",
        status: response.status,
      }, 502);
    } else {
      const openaiJson = await response.json();
      try {
        parsed = JSON.parse(extractOutputText(openaiJson));
      } catch (_error) {
        await supabase.from("raw_payment_sms").update({
          parse_status: "failed",
        })
          .eq("id", raw_sms_id);
        return jsonResponse(
          { error: "OpenAI parse returned invalid JSON" },
          502,
        );
      }
    }
    const senderHash = await hashPhone(optionalString(parsed.sender_phone));
    const receiverHash =
      await hashPhone(optionalString(parsed.receiver_phone)) ??
        rawSms.receiver_momo_number_hash;

    const { data: event, error: insertError } = await supabase
      .from("parsed_payment_events")
      .upsert({
        raw_sms_id,
        collection_id: rawSms.collection_id,
        receiver_user_id: rawSms.receiver_user_id,
        is_mobile_money_payment: parsed.is_mobile_money_payment,
        network: parsed.network,
        direction: parsed.direction,
        amount_rwf: parsed.amount_rwf,
        currency: parsed.currency,
        transaction_id: parsed.transaction_id,
        sender_name: null,
        sender_phone_hash: senderHash,
        receiver_phone_hash: receiverHash,
        transaction_time: parsed.transaction_time,
        detected_user_public_id: parsed.detected_user_public_id,
        confidence: parsed.confidence,
        parser_model: parserModel,
        parser_schema_version: parserSchemaVersion,
        parsed_json: sanitizeParsedJson(parsed),
        allocation_status: "unallocated",
      }, { onConflict: "raw_sms_id" })
      .select("id")
      .single();
    if (insertError) throw insertError;

    await supabase.from("raw_payment_sms").update({ parse_status: "parsed" })
      .eq("id", raw_sms_id);
    const { data: allocationStatus } = await supabase.rpc(
      "allocate_parsed_payment_event",
      { event_id: event.id },
    );
    return jsonResponse({
      ok: true,
      parsed_event_id: event.id,
      allocation_status: allocationStatus,
      parser_model: parserModel,
    });
  } catch (error) {
    if (rawSmsId) {
      try {
        await serviceClient().from("raw_payment_sms").update({
          parse_status: "failed",
        }).eq("id", rawSmsId);
      } catch {
        // Keep the public response safe even when the status update fails.
      }
    }
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({
      error: safeErrorMessage(error),
    }, 500);
  }
});
