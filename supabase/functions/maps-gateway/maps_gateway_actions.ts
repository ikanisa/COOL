import {
  asArray,
  asMap,
  asNumber,
  assertRwandaPoint,
  CACHE_TTL_AUTOCOMPLETE_MS,
  CACHE_TTL_REVERSE_GEOCODE_MS,
  clampInt,
  googleFetchJson,
  HttpError,
  isPlaceWithinRwanda,
  isWithinRwanda,
  MapsGatewayRequest,
  normalizeLanguageCode,
  normalizeTravelMode,
  parseLatLng,
  requireMapsApiKey,
  rwandaLocationRestriction,
  RWANDA_REGION_CODE,
  splitAddress,
  toPlaceResult,
} from "./maps_gateway_support.ts";

type CacheableMapsAction = "autocomplete" | "reverse_geocode";

export function isCacheableAction(
  action: MapsGatewayRequest["action"],
): action is CacheableMapsAction {
  return action == "autocomplete" || action == "reverse_geocode";
}

export function cacheTtlForAction(action: CacheableMapsAction): number {
  return action == "autocomplete"
    ? CACHE_TTL_AUTOCOMPLETE_MS
    : CACHE_TTL_REVERSE_GEOCODE_MS;
}

export async function handleAction(
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
    includedPrimaryTypes: [
      "route",
      "street_address",
      "establishment",
      "premise",
      "subpremise",
      "point_of_interest",
      "neighborhood",
      "sublocality",
      "locality",
    ],
  };

  const near = parseLatLng(body.near, "near");
  if (near && isWithinRwanda(near)) {
    payload.locationBias = {
      circle: {
        center: near,
        radius: 10000.0,
      },
    };
    payload.origin = near;
  }

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
          "suggestions.placePrediction.place,suggestions.placePrediction.placeId,suggestions.placePrediction.text.text,suggestions.placePrediction.structuredFormat.mainText.text,suggestions.placePrediction.structuredFormat.secondaryText.text,suggestions.placePrediction.distanceMeters",
      },
      body: JSON.stringify(payload),
    },
  );

  return asArray(response.suggestions)
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
        distanceMeters: asNumber(prediction.distanceMeters),
      };
    })
    .filter((prediction) => prediction.placeId && prediction.label)
    .slice(0, limit);
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
