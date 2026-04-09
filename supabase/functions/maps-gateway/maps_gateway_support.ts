export type LatLng = {
  latitude: number;
  longitude: number;
};

export type MapsGatewayRequest = {
  action?:
    | "autocomplete"
    | "text_search"
    | "place_details"
    | "reverse_geocode"
    | "compute_route";
  query?: string;
  placeId?: string;
  sessionToken?: string;
  languageCode?: string;
  limit?: number;
  near?: LatLng;
  location?: LatLng;
  origin?: LatLng;
  destination?: LatLng;
  travelMode?: string;
};

export const RWANDA_REGION_CODE = "rw";
const RWANDA_LANGUAGE_CODE = "en";
const RWANDA_BOUNDS = {
  low: { latitude: -2.95, longitude: 28.8 },
  high: { latitude: -1.0, longitude: 30.95 },
} as const;

const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 100;
export const CACHE_TTL_AUTOCOMPLETE_MS = 60 * 1000;
export const CACHE_TTL_REVERSE_GEOCODE_MS = 300 * 1000;
const CACHE_MAX_ENTRIES = 500;

export class RateLimiter {
  private buckets = new Map<string, { count: number; windowStart: number }>();

  allow(userId: string): boolean {
    const now = Date.now();
    const bucket = this.buckets.get(userId);

    if (!bucket || now - bucket.windowStart > RATE_LIMIT_WINDOW_MS) {
      this.buckets.set(userId, { count: 1, windowStart: now });
      return true;
    }

    bucket.count++;
    return bucket.count <= RATE_LIMIT_MAX_REQUESTS;
  }

  prune(): void {
    const now = Date.now();
    for (const [userId, bucket] of this.buckets) {
      if (now - bucket.windowStart > RATE_LIMIT_WINDOW_MS) {
        this.buckets.delete(userId);
      }
    }
  }
}

export class ResponseCache {
  private entries = new Map<
    string,
    { data: Record<string, unknown>; expiresAt: number }
  >();

  get(key: string): Record<string, unknown> | null {
    const entry = this.entries.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expiresAt) {
      this.entries.delete(key);
      return null;
    }
    return entry.data;
  }

  set(key: string, data: Record<string, unknown>, ttlMs: number): void {
    if (this.entries.size >= CACHE_MAX_ENTRIES) {
      const firstKey = this.entries.keys().next().value;
      if (firstKey !== undefined) this.entries.delete(firstKey);
    }
    this.entries.set(key, { data, expiresAt: Date.now() + ttlMs });
  }

  static key(action: string, params: Record<string, unknown>): string {
    const sorted = Object.keys(params)
      .sort()
      .map((key) => `${key}=${JSON.stringify(params[key])}`)
      .join("&");
    return `${action}:${sorted}`;
  }
}

export const mapsApiKeyConfig = resolveMapsApiKey();
const mapsApiKey = mapsApiKeyConfig.apiKey;

export async function googleFetchJson(
  url: string,
  init: RequestInit & { headers?: HeadersInit },
) {
  const response = await fetch(url, {
    ...init,
    headers: {
      "X-Goog-Api-Key": requireMapsApiKey(),
      ...(init.headers ?? {}),
    },
  });

  const json = await response.json().catch(() => null);
  if (!response.ok) {
    throw new HttpError(
      response.status,
      "Google Maps platform request failed",
      json,
    );
  }

  if (!json) {
    throw new HttpError(502, "Google Maps platform returned an empty response");
  }

  return json;
}

export function requireMapsApiKey(): string {
  if (!mapsApiKey) {
    throw new HttpError(
      500,
      "GOOGLE_MAPS_SERVER_API_KEY or GEMINI_API_KEY is not configured in Supabase secrets",
    );
  }

  return mapsApiKey;
}

function resolveMapsApiKey(): {
  apiKey: string | null;
  source:
    | "GOOGLE_MAPS_SERVER_API_KEY"
    | "GOOGLE_MAPS_API_KEY"
    | "GEMINI_API_KEY"
    | null;
} {
  for (
    const source of [
      "GOOGLE_MAPS_SERVER_API_KEY",
      "GOOGLE_MAPS_API_KEY",
      "GEMINI_API_KEY",
    ] as const
  ) {
    const value = Deno.env.get(source)?.trim();
    if (value) {
      return { apiKey: value, source };
    }
  }

  return { apiKey: null, source: null };
}

export function parseLatLng(
  value: unknown,
  fieldName: string,
): LatLng | null {
  const map = asMap(value);
  const latitude = asNumber(map.latitude);
  const longitude = asNumber(map.longitude);

  if (latitude == null || longitude == null) {
    return null;
  }

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new HttpError(400, `${fieldName} must contain valid coordinates`);
  }

  return { latitude, longitude };
}

export function rwandaLocationRestriction() {
  return {
    rectangle: {
      low: RWANDA_BOUNDS.low,
      high: RWANDA_BOUNDS.high,
    },
  };
}

export function isWithinRwanda(point: LatLng): boolean {
  return point.latitude >= RWANDA_BOUNDS.low.latitude &&
    point.latitude <= RWANDA_BOUNDS.high.latitude &&
    point.longitude >= RWANDA_BOUNDS.low.longitude &&
    point.longitude <= RWANDA_BOUNDS.high.longitude;
}

export function assertRwandaPoint(point: LatLng, fieldName: string) {
  if (!isWithinRwanda(point)) {
    throw new HttpError(400, `${fieldName} is outside the Rwanda market`);
  }
}

export function asMap(value: unknown): Record<string, any> {
  return value && typeof value == "object" && !Array.isArray(value)
    ? value as Record<string, any>
    : {};
}

export function asArray(value: unknown): any[] {
  return Array.isArray(value) ? value : [];
}

export function asNumber(value: unknown): number | null {
  if (typeof value == "number") {
    return value;
  }
  if (typeof value == "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function clampInt(
  value: unknown,
  min: number,
  max: number,
  fallback: number,
): number {
  const parsed = typeof value == "number"
    ? Math.trunc(value)
    : typeof value == "string"
    ? Math.trunc(Number(value))
    : fallback;
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, parsed));
}

export function normalizeLanguageCode(_value?: string): string {
  return RWANDA_LANGUAGE_CODE;
}

export function normalizeTravelMode(value?: string): string {
  const normalized = value?.trim().toUpperCase();
  if (normalized == "TWO_WHEELER") {
    return normalized;
  }
  return "DRIVE";
}

export function toPlaceResult(place: Record<string, any>) {
  const placeId = place.id?.toString().trim() ||
    place.name?.toString().replace(/^places\//, "").trim() ||
    null;
  const displayName = place.displayName?.text?.toString().trim() ?? "";
  const formattedAddress = place.formattedAddress?.toString().trim() ?? "";
  const [primaryText, secondaryText] = splitAddress(
    displayName,
    formattedAddress,
  );
  const location = parseLatLng(place.location, "location");

  return {
    placeId,
    label: secondaryText ? `${primaryText}, ${secondaryText}` : primaryText,
    primaryText,
    secondaryText,
    position: location,
  };
}

export function isPlaceWithinRwanda(place: Record<string, any>): boolean {
  const position = asMap(place.position);
  const latitude = asNumber(position.latitude);
  const longitude = asNumber(position.longitude);
  if (latitude == null || longitude == null) {
    return false;
  }
  return isWithinRwanda({ latitude, longitude });
}

export function splitAddress(
  primaryCandidate: string,
  fullAddress: string,
): [string, string | null] {
  const primary = primaryCandidate.trim();
  if (!fullAddress.trim()) {
    return [primary, null];
  }

  const parts = fullAddress
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (!parts.length) {
    return [primary || fullAddress.trim(), null];
  }

  const fallbackPrimary = primary || parts[0];
  const secondaryParts = parts.filter((part) =>
    part.toLowerCase() != fallbackPrimary.toLowerCase()
  );

  return [
    fallbackPrimary,
    secondaryParts.length ? secondaryParts.join(", ") : null,
  ];
}

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
  }
}
