// Loads the Google Maps JavaScript API script at most once per page,
// regardless of how many times a component using it mounts (e.g. React
// Strict Mode's double-invoked effects in development, or navigating
// between screens that each render a map).

const SCRIPT_ATTR = 'data-achaago-google-maps';

type GoogleMapsNamespace = typeof google.maps;

function existingGoogle(): GoogleMapsNamespace | undefined {
  return (window as unknown as {google?: {maps?: GoogleMapsNamespace}}).google?.maps;
}

let loadPromise: Promise<GoogleMapsNamespace> | null = null;

export function loadGoogleMaps(apiKey: string): Promise<GoogleMapsNamespace> {
  if (typeof window === 'undefined') return Promise.reject(new Error('Google Maps can only load in the browser'));
  const already = existingGoogle();
  if (already) return Promise.resolve(already);
  if (loadPromise) return loadPromise;

  loadPromise = new Promise<GoogleMapsNamespace>((resolve, reject) => {
    const onReady = () => {
      const maps = existingGoogle();
      if (maps) resolve(maps);
      else reject(new Error('Google Maps failed to initialize'));
    };
    const existingScript = document.querySelector<HTMLScriptElement>(`script[${SCRIPT_ATTR}]`);
    if (existingScript) {
      existingScript.addEventListener('load', onReady, {once: true});
      existingScript.addEventListener('error', () => reject(new Error('Google Maps script failed to load')), {once: true});
      return;
    }
    const script = document.createElement('script');
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&v=weekly&loading=async`;
    script.async = true;
    script.setAttribute(SCRIPT_ATTR, 'true');
    script.addEventListener('load', onReady, {once: true});
    script.addEventListener('error', () => reject(new Error('Google Maps script failed to load')), {once: true});
    document.head.appendChild(script);
  });

  // Let a later mount try again instead of being stuck with a rejected
  // singleton forever (e.g. a transient network blip).
  loadPromise.catch(() => {
    loadPromise = null;
  });

  return loadPromise;
}

export type LocationPermission = 'unknown' | 'granted' | 'prompt' | 'denied';

/** Best-effort, non-prompting read of the current geolocation permission.
 *  Never triggers the browser's permission dialog itself — that stays the
 *  job of the existing `navigator.geolocation.getCurrentPosition` call in
 *  CustomerFlow, so the user is never prompted twice. */
export async function readLocationPermission(): Promise<LocationPermission> {
  try {
    if (!navigator.permissions?.query) return 'unknown';
    const status = await navigator.permissions.query({name: 'geolocation'});
    return status.state;
  } catch {
    // Older Safari, or a browser that doesn't support querying this
    // permission at all: treat as unknown rather than denied so the real
    // map still gets a chance to load.
    return 'unknown';
  }
}

export type MapSdkState = 'idle' | 'loading' | 'loaded' | 'error';

/** Pure decision: should the real Google Map render, or the decorative
 *  fallback? Kept dependency-free and exported on its own so it can be
 *  unit tested without a DOM or the Maps SDK once this project has a unit
 *  test runner (see apps/web's README for the current testing gap). */
export function shouldShowRealMap(input: {hasApiKey: boolean; sdkState: MapSdkState; locationPermission: LocationPermission}): boolean {
  if (!input.hasApiKey) return false;
  if (input.locationPermission === 'denied') return false;
  return input.sdkState === 'loaded';
}
