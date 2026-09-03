export type SmsIntegrityRequest = {
  subjectId: string;
  nonce: string;
  receiverMomoNumberHash: string;
  clientEnvelopeId: string;
  rawSender: string;
  rawBodySha256: string;
  receivedAtDevice: string | null;
};

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function smsIntegrityPayload(input: SmsIntegrityRequest) {
  return {
    action: "sms.ingest",
    subject_id: input.subjectId,
    nonce: input.nonce,
    receiver_momo_number_hash: input.receiverMomoNumberHash,
    sms_permission_granted: true,
    sms_access_enabled: true,
    sms_request: {
      client_envelope_id: input.clientEnvelopeId,
      raw_sender: input.rawSender,
      raw_body_sha256: input.rawBodySha256,
      received_at_device: input.receivedAtDevice,
    },
  };
}

export function smsCapabilityPayload(input: SmsIntegrityRequest) {
  return {
    receiver_momo_number_hash: input.receiverMomoNumberHash,
    client_envelope_id: input.clientEnvelopeId,
    raw_sender: input.rawSender,
    raw_body_sha256: input.rawBodySha256,
    received_at_device: input.receivedAtDevice,
  };
}

export async function smsIntegrityRequestHash(
  input: SmsIntegrityRequest,
): Promise<string> {
  return await sha256Hex(JSON.stringify(smsIntegrityPayload(input)));
}
