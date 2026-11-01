import type {D1Database} from "./postgres.ts";
export const KINDS = ["otp", "receipt", "operation", "campaign"] as const;
export type Kind = (typeof KINDS)[number];
export const SCOPES = [
  "messages:write",
  "messages:read",
  "messages:cancel",
  "otp",
  "contributions",
  "campaigns",
] as const;
export type Scope = (typeof SCOPES)[number];
export const PRIORITIES: Record<Kind, number> = {
  otp: 120,
  receipt: 80,
  operation: 50,
  campaign: 10,
};
export const EVENT_TYPES = [
  "phone_accepted",
  "handoff_started",
  "part_sent",
  "part_delivered",
  "part_failed",
  "outcome_unknown",
  "expired",
  "cancelled",
  "failed",
] as const;
export type EventType = (typeof EVENT_TYPES)[number];
export const STAFF_ROLES = ["administrator", "operator", "viewer"] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];
export type AdminPermission = "read" | "messages:cancel" | "campaigns:write" | "applications:write" | "devices:write" | "staff:manage" | "retention:manage" | "audit:read";
export interface Env {
  DB: D1Database;
  COLLECT_FENCE_WORK?: unknown;
  FETCH?: typeof fetch;
  REQUIRE_ACTUAL_PARTS?: string;
  ROOT_ADMIN_TOKEN: string;
  OTP_HMAC_KEY: string;
  OTP_REQUIRE_READY_GATEWAY?: string;
  ENVIRONMENT?: string;
  ALLOW_INSECURE_LOCALHOST?: string;
  ADMIN_ORIGIN?: string;
  FCM_ENABLED?: string;
  OTP_SEGMENT_INTERVAL_MS?: string;
  DISPATCH_PAUSED?: string;
  CALLBACK_ENCRYPTION_KEY?: string;
  CALLBACK_ALLOWED_HOSTS?: string;
  CALLBACK_ALLOW_LOCAL_TEST?: string;
  MESSAGE_RETENTION_DAYS?: string;
  RETENTION_AUTO_PURGE?: string;
  FCM_PROJECT_ID?: string;
  FCM_CLIENT_EMAIL?: string;
  FCM_PRIVATE_KEY?: string;
}
export type Principal =
  | { type: "admin"; id: string; name: string; role: StaffRole; sessionId?: string }
  | { type: "application"; id: string; allowedKinds: Kind[]; scopes: Scope[] }
  | { type: "device"; id: string; allowedKinds: Kind[] };
export type AppEnv = { Bindings: Env; Variables: { principal: Principal } };
export interface MessageRow {
  message_id: string;
  application_id: string;
  kind: Kind;
  to_number: string;
  text: string;
  payload_digest: string;
  request_digest: string;
  idempotency_key: string;
  priority: number;
  not_after: string;
  available_at: string;
  owner_installation_id: string | null;
  assignment_version: number;
  state: string;
  cancel_requested: number;
  created_at: string;
  updated_at: string;
  phone_accepted_at: string | null;
  campaign_id: string | null;
  otp_challenge_id: string | null;
  metadata_json: string;
  requires_fresh_decision: number;
  eligibility_until: string | null;
  segments_estimate: number;
  unknown_observed: number;
  failure_observed: number;
  content_redacted_at: string | null;
  content_hold: number;
}
export interface DeviceRow {
  installation_id: string;
  name: string;
  token_hash: string;
  allowed_kinds: string;
  sim_slot: number | null;
  ready: number;
  revoked_at: string | null;
  created_at: string;
  last_seen_at: string | null;
  app_version: string | null;
  os_version: string | null;
  fcm_token: string | null;
  fcm_rejected_token_hash: string | null;
  fcm_pending: number;
  fcm_next_at: string | null;
  fcm_attempts: number;
  fcm_last_error: string | null;
  health_json: string;
}
export interface Job {
  message_id: string;
  application_id: string;
  kind: Kind;
  to: string;
  text: string;
  payload_digest: string;
  priority: number;
  not_after: string;
  available_at: string;
  owner_installation_id: string;
  assignment_version: number;
  sim_slot?: number;
  campaign_id?: string;
}
export interface DeviceEvent {
  event_id: string;
  message_id: string;
  assignment_version: number;
  attempt_id?: string;
  type: EventType;
  at: string;
  part_index?: number;
  parts_total?: number;
  error_code?: string;
  detail?: unknown;
}
