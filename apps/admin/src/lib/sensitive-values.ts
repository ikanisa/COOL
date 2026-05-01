const SENSITIVE_CONFIG_KEY =
  /(^|[_.:-])(secret|token|password|passwd|private|service[_-]?role|api[_-]?key|anon[_-]?key|jwt|credential|credentials|webhook|signing|salt)([_.:-]|$)/i;

export interface MaskedConfigValue {
  value: string;
  masked: boolean;
}

export function isSensitiveConfigKey(key: string): boolean {
  return SENSITIVE_CONFIG_KEY.test(key.trim());
}

export function maskConfigValue(key: string, value: string | null | undefined): MaskedConfigValue {
  const raw = value ?? "";
  if (!isSensitiveConfigKey(key)) {
    return { value: raw || "—", masked: false };
  }

  if (!raw) {
    return { value: "Not set", masked: true };
  }

  return { value: "••••••••", masked: true };
}
