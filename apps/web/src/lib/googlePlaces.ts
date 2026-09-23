// Wraps the classic Places JavaScript library (AutocompleteService +
// PlacesService) for the destination search box on the route screen.
// Requires `libraries=places` in the Maps script URL (see googleMaps.ts)
// and the "Places API" enabled on the project — see README.md
// "Google Maps (web)".
//
// The two pure functions below (`mapPrediction`, `shouldFallbackToDemo`)
// have no browser/DOM dependency and can be run and tested directly with
// Node's built-in test runner: from apps/web,
//   node --experimental-strip-types --test src/lib/googlePlaces.test.ts

export type PlaceSuggestion = {id: string; address: string};

/** Turns a raw Places prediction into the same {id,address} shape the
 *  app's demo `/places` search already returns, so the rest of
 *  CustomerFlow doesn't need to know which source a suggestion came from. */
export function mapPrediction(prediction: {place_id: string; description: string}): PlaceSuggestion {
  return {id: prediction.place_id, address: prediction.description};
}

/** Does this AutocompleteService/PlacesService status mean the caller
 *  should fall back to the demo `/places` search (key missing/invalid,
 *  Places API not enabled, quota exceeded, ...) rather than a legitimate
 *  "no matches" for this particular query? */
export function shouldFallbackToDemo(status: string): boolean {
  return status !== 'OK' && status !== 'ZERO_RESULTS';
}

const UB_CENTER = {lat: 47.9186, lng: 106.9177};

function placesLibrary(): typeof google.maps.places | null {
  return (window as unknown as {google?: {maps?: {places?: typeof google.maps.places}}}).google?.maps?.places ?? null;
}

export function isGooglePlacesAvailable(): boolean {
  return placesLibrary() !== null;
}

let autocompleteService: google.maps.places.AutocompleteService | null = null;
let placesService: google.maps.places.PlacesService | null = null;

function getAutocompleteService(): google.maps.places.AutocompleteService | null {
  const places = placesLibrary();
  if (!places) return null;
  if (!autocompleteService) autocompleteService = new places.AutocompleteService();
  return autocompleteService;
}

function getPlacesService(): google.maps.places.PlacesService | null {
  const places = placesLibrary();
  if (!places) return null;
  if (!placesService) placesService = new places.PlacesService(document.createElement('div'));
  return placesService;
}

/** One token per typing session (created on the first keystroke, reused
 *  across every prediction call, spent on the Place Details call) so
 *  Google bills the whole search-then-select sequence as a single
 *  session instead of N separate autocomplete requests. */
export function createSessionToken(): google.maps.places.AutocompleteSessionToken | null {
  const places = placesLibrary();
  return places ? new places.AutocompleteSessionToken() : null;
}

export function searchGooglePlaces(
  input: string,
  sessionToken: google.maps.places.AutocompleteSessionToken | null,
): Promise<PlaceSuggestion[]> {
  return new Promise((resolve, reject) => {
    const service = getAutocompleteService();
    if (!service) {
      reject(new Error('Places library not loaded'));
      return;
    }
    service.getPlacePredictions(
      {
        input,
        sessionToken: sessionToken ?? undefined,
        componentRestrictions: {country: 'mn'},
        locationBias: {center: UB_CENTER, radius: 60000},
      },
      (predictions, status) => {
        if (status === 'ZERO_RESULTS') {
          resolve([]);
          return;
        }
        if (shouldFallbackToDemo(status) || !predictions) {
          reject(new Error(`Places autocomplete failed: ${status}`));
          return;
        }
        resolve(predictions.map(mapPrediction));
      },
    );
  });
}

export type PlaceDetails = {lat: number; lng: number; address: string};

/** Only fetched once the user picks a suggestion — never while typing —
 *  and field-masked to the cheapest ("Basic Data") tier: just the
 *  coordinates and a display address, nothing else. */
export function getGooglePlaceDetails(
  placeId: string,
  sessionToken: google.maps.places.AutocompleteSessionToken | null,
): Promise<PlaceDetails> {
  return new Promise((resolve, reject) => {
    const service = getPlacesService();
    if (!service) {
      reject(new Error('Places library not loaded'));
      return;
    }
    service.getDetails(
      {placeId, sessionToken: sessionToken ?? undefined, fields: ['geometry', 'formatted_address']},
      (place, status) => {
        if (shouldFallbackToDemo(status) || !place?.geometry?.location) {
          reject(new Error(`Place details failed: ${status}`));
          return;
        }
        resolve({
          lat: place.geometry.location.lat(),
          lng: place.geometry.location.lng(),
          address: place.formatted_address ?? '',
        });
      },
    );
  });
}
