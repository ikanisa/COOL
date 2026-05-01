/**
 * ledger_writer.ts — Persistence layer for parsed SMS results.
 *
 * Handles upserts to:
 * - `momo_sms_parsed`      (parsed SMS record)
 * - `momo_ledger_entries`   (financial ledger entry)
 * - `momo_reconciliations`  (reconciliation result)
 */

import type { createAdminClient } from "../_shared/supabase.ts";
import type { ParsedSms, ParseProvider, RawSmsRecord } from "./ai_parser.ts";
import { asString, deriveLedgerScope } from "./parse_helpers.ts";
import { ledgerEntryType } from "./reconciliation.ts";
import type { AutoReconciliationResult } from "./reconciliation_utils.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

// ── Parsed SMS upsert ──────────────────────────────────────────

export type UpsertParsedSmsParams = {
  rawSms: RawSmsRecord;
  parsed: ParsedSms;
  provider: ParseProvider;
  model: string;
  timestamp: string;
};

/**
 * Upsert the AI-parsed SMS into `momo_sms_parsed`.
 * @returns The newly-created parsed_sms_id.
 */
export async function upsertParsedSms(
  adminClient: AdminClient,
  params: UpsertParsedSmsParams,
): Promise<string> {
  const { rawSms, parsed, provider, model, timestamp } = params;

  const result = await adminClient
    .from("momo_sms_parsed")
    .upsert({
      raw_sms_id: rawSms.id,
      user_id: rawSms.user_id,
      parser_provider: provider,
      parser_model: model,
      parse_status: parsed.parse_status,
      confidence: parsed.confidence,
      tx_direction: parsed.tx_direction,
      tx_type: parsed.tx_type,
      tx_category: parsed.tx_category,
      cashflow_bucket: parsed.cashflow_bucket,
      momo_tx_id: parsed.momo_tx_id,
      amount: parsed.amount,
      currency: parsed.currency,
      tx_date: parsed.tx_date,
      tx_time: parsed.tx_time,
      tx_datetime: parsed.tx_datetime_iso,
      payer_name: parsed.payer_name,
      payer_number_last3: parsed.payer_number_last3,
      payer_number_full: parsed.payer_number_full,
      payee_name: parsed.payee_name,
      payee_number_or_code: parsed.payee_number_or_code,
      merchant_code: parsed.merchant_code,
      fee_amount: parsed.fee_amount,
      balance_after: parsed.balance_after,
      counterparty_name: parsed.counterparty_name,
      ai_summary: parsed.ai_summary,
      recurring_pattern_hint: parsed.recurring_pattern_hint,
      narrative: parsed.narrative ?? parsed.notes,
      structured_data: parsed,
      updated_at: timestamp,
    }, { onConflict: "raw_sms_id" })
    .select("id")
    .single();

  if (result.error) {
    throw result.error;
  }

  return result.data.id as string;
}

// ── Ledger entry upsert ────────────────────────────────────────

export type UpsertLedgerEntryParams = {
  parsedSmsId: string;
  rawSms: RawSmsRecord;
  parsed: ParsedSms;
  provider: ParseProvider;
  model: string;
  reconciliation: AutoReconciliationResult;
  timestamp: string;
};

/**
 * Upsert a ledger entry into `momo_ledger_entries`.
 * Only writes when there is a valid amount and a matched reconciliation.
 */
export async function upsertLedgerEntry(
  adminClient: AdminClient,
  params: UpsertLedgerEntryParams,
): Promise<void> {
  const { parsed, reconciliation } = params;

  // Gate: only write ledger entries for matched, positive-amount transactions
  if (
    parsed.amount == null ||
    parsed.amount <= 0 ||
    reconciliation.matchStatus !== "matched"
  ) {
    return;
  }

  const payeeGroupId = asString(reconciliation.metadata.group_id);
  const payeePartnerId = asString(reconciliation.metadata.partner_id);

  const result = await adminClient
    .from("momo_ledger_entries")
    .upsert({
      parsed_sms_id: params.parsedSmsId,
      user_id: params.rawSms.user_id,
      entry_type: ledgerEntryType(parsed),
      ledger_scope: deriveLedgerScope(reconciliation.targetTable),
      ledger_status: reconciliation.ledgerStatus,
      amount: parsed.amount,
      currency: parsed.currency,
      tx_datetime: parsed.tx_datetime_iso ?? params.rawSms.sms_received_at,
      tx_category: parsed.tx_category,
      cashflow_bucket: parsed.cashflow_bucket,
      counterparty_name: parsed.counterparty_name,
      statement_label: parsed.ai_summary ??
        parsed.narrative ??
        `Mobile money ${parsed.tx_type}`,
      external_reference: parsed.momo_tx_id ??
        reconciliation.matchedReference,
      target_table: reconciliation.targetTable,
      target_record_id: reconciliation.targetRecordId,
      payee_group_id: payeeGroupId,
      payee_partner_id: payeePartnerId,
      description: parsed.ai_summary ??
        parsed.narrative ??
        `AI parsed ${parsed.tx_type} from MoMo SMS`,
      metadata: {
        parser_provider: params.provider,
        parser_model: params.model,
        confidence: parsed.confidence,
        tx_category: parsed.tx_category,
        cashflow_bucket: parsed.cashflow_bucket,
        recurring_pattern_hint: parsed.recurring_pattern_hint,
        source_raw_sms_id: params.rawSms.id,
        matched_reference: reconciliation.matchedReference,
        ...reconciliation.metadata,
      },
      updated_at: params.timestamp,
    }, { onConflict: "parsed_sms_id" });

  if (result.error) {
    throw result.error;
  }
}

// ── Reconciliation upsert ──────────────────────────────────────

export type UpsertReconciliationParams = {
  parsedSmsId: string;
  rawSms: RawSmsRecord;
  parsed: ParsedSms;
  provider: ParseProvider;
  model: string;
  reconciliation: AutoReconciliationResult;
  timestamp: string;
};

/**
 * Upsert the reconciliation result into `momo_reconciliations`.
 */
export async function upsertReconciliation(
  adminClient: AdminClient,
  params: UpsertReconciliationParams,
): Promise<void> {
  const { parsedSmsId, rawSms, parsed, provider, model, reconciliation, timestamp } = params;

  const result = await adminClient
    .from("momo_reconciliations")
    .upsert({
      parsed_sms_id: parsedSmsId,
      user_id: rawSms.user_id,
      target_table: reconciliation.targetTable,
      target_record_id: reconciliation.targetRecordId,
      match_type: reconciliation.matchType,
      match_status: reconciliation.matchStatus,
      confidence: parsed.confidence,
      notes: reconciliation.notes ?? parsed.notes,
      metadata: {
        parser_provider: provider,
        parser_model: model,
        source_raw_sms_id: rawSms.id,
        matched_reference: reconciliation.matchedReference,
        ...reconciliation.metadata,
      },
      reconciled_at: reconciliation.matchStatus === "matched"
        ? timestamp
        : null,
      updated_at: timestamp,
    }, { onConflict: "parsed_sms_id" });

  if (result.error) {
    throw result.error;
  }
}
