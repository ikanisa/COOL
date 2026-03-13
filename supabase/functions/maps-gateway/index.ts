import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type LatLng = {
  latitude: number;
  longitude: number;
};

type MapsGatewayRequest = {
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

const RWANDA_REGION_CODE = "rw";
const RWANDA_LANGUAGE_CODE = "en";
const RWANDA_BOUNDS = {
  low: { latitude: -2.95, longitude: 28.8 },
  high: { latitude: -1.0, longitude: 30.95 },
} as const;

const mapsApiKeyConfig = resolveMapsApiKey();
const mapsApiKey = mapsApiKeyConfig.apiKey;

if (!mapsApiKey) {
  console.warn(
    "maps-gateway loaded without GOOGLE_MAPS_SERVER_API_KEY or GEMINI_API_KEY. Requests will fail until a Google credential is configured.",
  );
} else if (mapsApiKeyConfig.source == "GEMINI_API_KEY") {
  console.info(
    "maps-gateway is using GEMINI_API_KEY as its Google Maps Platform credential.",
  );
}

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required", 401);
  }

  let userIdForTelemetry: string | null = null;

  try {
    const user = await requireUser(authorization);
    userIdForTelemetry = user.id;
    const body = await request.json() as MapsGatewayRequest;
    const startedAt = Date.now();

    const response = await handleAction(body);

    console.info(
      JSON.stringify({
        service: "maps-gateway",
        user_id: user.id,
        action: body.action ?? "unknown",
        latency_ms: Date.now() - startedAt,
      }),
    );

    return jsonResponse({ success: true, ...response });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body", 400);
    }

    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status, error.details);
    }

    console.error("maps-gateway failed", error);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "maps-gateway",
      error,
      userId: userIdForTelemetry,
    });
    return errorResponse(
      error instanceof Error ? error.message : "Maps gateway failed",
      500,
    );
  }
});

async function requireUser(authorization: string) {
  const client = createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await client.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required");
  }

  return user;
}

async function handleAction(
  body: MapsGatewayRequest,
): Promise<Record<string, unknown>> {
  switch (body.action) {
    case "autocomplete":
      return { suggestions: await autocompletePlaces(body) };
    case "text_search":
      return { places: await textSearchPlaces(body) };
    case "place_details":
      return { place: await fetchPlaceDetails(body) };
    case "reverse_geocode":
      return { place: await reverseGeocode(body) };
    case "compute_route":
      return { route: await computeRoute(body) };
    default:
      throw new HttpError(400, "Unsupported maps action", {
        action: body.action ?? null,
      });
  }
}

async function autocompletePlaces(body: MapsGatewayRequest) {
  const query = body.query?.trim() ?? "";
  if (query.length < 3) {
    return [];
  }

  const limit = clampInt(body.limit, 1, 8, 5);
  const payload: Record<string, unknown> = {
    input: query,
    includeQueryPredictions: false,
    includedRegionCodes: [RWANDA_REGION_CODE],
    locationRestriction: rwandaLocationRestriction(),
    regionCode: RWANDA_REGION_CODE,
  };

  const languageCode = normalizeLanguageCode(body.languageCode);
  if (languageCode) {
    payload.languageCode = languageCode;
  }

  const sessionToken = body.sessionToken?.trim();
  if (sessionToken) {
    payload.sessionToken = sessionToken;
  }

  const response = await googleFetchJson(
    "https://places.googleapis.com/v1/places:autocomplete",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-FieldMask":
          "suggestions.placePrediction.place,suggestions.placePrediction.placeId,suggestions.placePrediction.text.text,suggestions.placePrediction.structuredFormat.mainText.text,suggestions.placePrediction.structuredFormat.secondaryText.text",
      },
      body: JSON.stringify(payload),
    },
  );

  const suggestions = asArray(response.suggestions)
    .map((item) => asMap(item.placePrediction))
    .filter((prediction) => Object.keys(prediction).length > 0)
    .map((prediction) => {
      const primaryText =
        prediction.structuredFormat?.mainText?.text?.toString().trim() ??
          prediction.text?.text?.toString().trim() ??
          "";
      const secondaryText = prediction.structuredFormat?.secondaryText?.text
        ?.toString()
        .trim();
      const placeId = prediction.placeId?.toString().trim() ||
        prediction.place?.toString().replace(/^places\//, "").trim();
      const label = secondaryText
        ? `${primaryText}, ${secondaryText}`
        : primaryText;

      return {
        placeId,
        label,
        primaryText,
        secondaryText: secondaryText || null,
      };
    })
    .filter((prediction) => prediction.placeId && prediction.label)
    .slice(0, limit);

  return suggestions;
}

async function textSearchPlaces(body: MapsGatewayRequest) {
  const query = body.query?.trim() ?? "";
  if (query.length < 3) {
    return [];
  }

  const limit = clampInt(body.limit, 1, 5, 1);
  const payload: Record<string, unknown> = {
    textQuery: query,
    pageSize: limit,
    rankPreference: "RELEVANCE",
    locationRestriction: rwandaLocationRestriction(),
    regionCode: RWANDA_REGION_CODE,
  };

  const languageCode = normalizeLanguageCode(body.languageCode);
  if (languageCode) {
    payload.languageCode = languageCode;
  }

  const response = await googleFetchJson(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.location",
      },
      body: JSON.stringify(payload),
    },
  );

  return asArray(response.places)
    .map((item) => toPlaceResult(asMap(item)))
    .filter((place) => isPlaceWithinRwanda(place))
    .filter((place) => place.placeId && place.label && place.position)
    .slice(0, limit);
}

async function fetchPlaceDetails(body: MapsGatewayRequest) {
  const placeId = body.placeId?.trim();
  if (!placeId) {
    throw new HttpError(400, "placeId is required for place_details");
  }

  const url = new URL(
    `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
  );
  const languageCode = normalizeLanguageCode(body.languageCode);
  if (languageCode) {
    url.searchParams.set("languageCode", languageCode);
  }
  url.searchParams.set("regionCode", RWANDA_REGION_CODE);
  if (body.sessionToken?.trim()) {
    url.searchParams.set("sessionToken", body.sessionToken.trim());
  }

  const response = await googleFetchJson(url.toString(), {
    headers: {
      "X-Goog-FieldMask": "id,displayName,formattedAddress,location",
    },
  });

  const place = toPlaceResult(asMap(response));
  if (!place.position) {
    throw new HttpError(502, "Google Place Details did not return coordinates");
  }
  if (!isPlaceWithinRwanda(place)) {
    throw new HttpError(400, "Place is outside the Rwanda market");
  }

  return place;
}

async function reverseGeocode(body: MapsGatewayRequest) {
  const location = parseLatLng(body.location, "location");
  if (!location) {
    throw new HttpError(400, "location is required for reverse_geocode");
  }
  assertRwandaPoint(location, "location");

  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("latlng", `${location.latitude},${location.longitude}`);
  url.searchParams.set("key", requireMapsApiKey());
  url.searchParams.set("region", RWANDA_REGION_CODE.toLowerCase());

  const languageCode = normalizeLanguageCode(body.languageCode);
  if (languageCode) {
    url.searchParams.set("language", languageCode);
  }

  const response = await fetch(url.toString());
  const json = await response.json();
  if (!response.ok) {
    throw new HttpError(
      response.status,
      "Reverse geocoding request failed",
      json,
    );
  }

  if (json.status != "OK") {
    if (json.status == "ZERO_RESULTS") {
      return null;
    }
    throw new HttpError(502, "Reverse geocoding failed", json);
  }

  const firstResult = asArray(json.results)[0];
  if (!firstResult) {
    return null;
  }

  const formattedAddress = firstResult.formatted_address?.toString().trim() ??
    "";
  const [primaryText, secondaryText] = splitAddress("", formattedAddress);

  return {
    placeId: firstResult.place_id?.toString() ?? null,
    label: secondaryText ? `${primaryText}, ${secondaryText}` : primaryText,
    primaryText,
    secondaryText,
    position: location,
  };
}

async function computeRoute(body: MapsGatewayRequest) {
  const origin = parseLatLng(body.origin, "origin");
  const destination = parseLatLng(body.destination, "destination");
  if (!origin || !destination) {
    throw new HttpError(
      400,
      "origin and destination are required for compute_route",
    );
  }
  assertRwandaPoint(origin, "origin");
  assertRwandaPoint(destination, "destination");

  const travelMode = normalizeTravelMode(body.travelMode);
  const payload: Record<string, unknown> = {
    origin: {
      location: {
        latLng: origin,
      },
    },
    destination: {
      location: {
        latLng: destination,
      },
    },
    travelMode,
    routingPreference: "TRAFFIC_AWARE",
    computeAlternativeRoutes: false,
    polylineQuality: "OVERVIEW",
    units: "METRIC",
  };

  const languageCode = normalizeLanguageCode(body.languageCode);
  if (languageCode) {
    payload.languageCode = languageCode;
  }

  const response = await googleFetchJson(
    "https://routes.googleapis.com/directions/v2:computeRoutes",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-FieldMask":
          "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline",
      },
      body: JSON.stringify(payload),
    },
  );

  const firstRoute = asArray(response.routes)[0];
  if (!firstRoute) {
    return null;
  }

  return {
    distanceMeters: clampInt(
      firstRoute.distanceMeters,
      0,
      Number.MAX_SAFE_INTEGER,
      0,
    ),
    duration: firstRoute.duration?.toString() ?? "0s",
    encodedPolyline: firstRoute.polyline?.encodedPolyline?.toString() ?? "",
    travelMode,
  };
}

async function googleFetchJson(
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

function requireMapsApiKey(): string {
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

function parseLatLng(value: unknown, fieldName: string): LatLng | null {
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

function rwandaLocationRestriction() {
  return {
    rectangle: {
      low: RWANDA_BOUNDS.low,
      high: RWANDA_BOUNDS.high,
    },
  };
}

function isWithinRwanda(point: LatLng): boolean {
  return point.latitude >= RWANDA_BOUNDS.low.latitude &&
    point.latitude <= RWANDA_BOUNDS.high.latitude &&
    point.longitude >= RWANDA_BOUNDS.low.longitude &&
    point.longitude <= RWANDA_BOUNDS.high.longitude;
}

function assertRwandaPoint(point: LatLng, fieldName: string) {
  if (!isWithinRwanda(point)) {
    throw new HttpError(400, `${fieldName} is outside the Rwanda market`);
  }
}

function asMap(value: unknown): Record<string, any> {
  return value && typeof value == "object" && !Array.isArray(value)
    ? value as Record<string, any>
    : {};
}

function asArray(value: unknown): any[] {
  return Array.isArray(value) ? value : [];
}

function asNumber(value: unknown): number | null {
  if (typeof value == "number") {
    return value;
  }
  if (typeof value == "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function clampInt(
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

function normalizeLanguageCode(value?: string): string | null {
  const normalized = value?.trim().toLowerCase();
  if (!normalized) {
    return RWANDA_LANGUAGE_CODE;
  }
  return normalized.startsWith("en")
    ? RWANDA_LANGUAGE_CODE
    : RWANDA_LANGUAGE_CODE;
}

function normalizeTravelMode(value?: string): string {
  const normalized = value?.trim().toUpperCase();
  if (normalized == "TWO_WHEELER") {
    return normalized;
  }
  return "DRIVE";
}

function toPlaceResult(place: Record<string, any>) {
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

function isPlaceWithinRwanda(place: Record<string, any>): boolean {
  const position = asMap(place.position);
  const latitude = asNumber(position.latitude);
  const longitude = asNumber(position.longitude);
  if (latitude == null || longitude == null) {
    return false;
  }
  return isWithinRwanda({ latitude, longitude });
}

function splitAddress(
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

class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
  }
}
