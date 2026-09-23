// Wraps the current Places API (New) data API for the destination search
// box on the route screen. It deliberately does not call the deprecated
// AutocompleteService or PlacesService classes.
//
// The pure functions below (`mapPrediction`, `shouldFallbackToDemo`,
// `createStaleGuard`, `cycleHighlight`) have no browser/DOM dependency and
// can be run and tested directly with Node's built-in test runner: from
// apps/web,
//   node --experimental-strip-types --test src/lib/googlePlaces.test.ts

export type PlaceSuggestion = {id: string; address: string; place?: unknown};

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

export type StaleGuard = {start: () => number; isCurrent: (token: number) => boolean};

/** Guards against a slow, older search response overwriting a faster,
 *  newer one while the customer keeps typing. `start()` marks a new
 *  in-flight request and returns its token; `isCurrent(token)` tells the
 *  caller, once that request resolves, whether it's still the latest one
 *  worth applying (a later `start()` call — from a newer keystroke or an
 *  Escape key — invalidates every earlier token). */
export function createStaleGuard(): StaleGuard {
  let latest = 0;
  return {
    start: () => ++latest,
    isCurrent: (token: number) => token === latest,
  };
}

/** Moves the highlighted suggestion index for ArrowUp/ArrowDown, wrapping
 *  around at both ends. `-1` means "nothing highlighted yet": ArrowDown
 *  starts at the first suggestion, ArrowUp starts at the last one — the
 *  usual combobox convention. */
export function cycleHighlight(current: number, length: number, direction: 1 | -1): number {
  if (length === 0) return -1;
  if (current === -1) return direction === 1 ? 0 : length - 1;
  return (current + direction + length) % length;
}

const UB_CENTER = {lat: 47.9186, lng: 106.9177};

function placesLibrary(): typeof google.maps.places | null {
  return (window as unknown as {google?: {maps?: {places?: typeof google.maps.places}}}).google?.maps?.places ?? null;
}

export function isGooglePlacesAvailable(): boolean {
  const maps = (window as unknown as {google?: {maps?: {importLibrary?: unknown}}}).google?.maps;
  return typeof maps?.importLibrary === 'function';
}

/** One token per typing session (created on the first keystroke, reused
 *  across every prediction call, then spent by Place.fetchFields()) so
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
  const maps = (window as unknown as {google?: {maps?: {importLibrary?: (name: string) => Promise<unknown>}}}).google?.maps;
  if (!maps?.importLibrary) return Promise.reject(new Error('Places API (New) library not loaded'));
  return maps.importLibrary('places').then((library: any) => library.AutocompleteSuggestion.fetchAutocompleteSuggestions({
    input,
    sessionToken: sessionToken ?? undefined,
    includedRegionCodes: ['mn'],
    language: 'mn',
  })).then(({suggestions}: {suggestions: any[]}) => suggestions.flatMap(suggestion => {
    const prediction = suggestion.placePrediction;
    if (!prediction) return [];
    const place = prediction.toPlace();
    return [{id: place.id, address: prediction.text.toString(), place}];
  }));
}

export type PlaceDetails = {lat: number; lng: number; address: string};

/** Only fetched once the user picks a suggestion — never while typing —
 *  and field-masked to the cheapest ("Basic Data") tier: just the
 *  coordinates and a display address, nothing else. */
export function getGooglePlaceDetails(
  selectedPlace: unknown,
): Promise<PlaceDetails> {
  const place = selectedPlace as any;
  if (!place?.fetchFields) return Promise.reject(new Error('Selected place is unavailable'));
  return place.fetchFields({fields: ['location', 'formattedAddress']}).then(() => {
    if (!place.location) throw new Error('Selected place has no location');
    return {
      lat: place.location.lat(),
      lng: place.location.lng(),
      address: place.formattedAddress ?? '',
    };
  });
}
