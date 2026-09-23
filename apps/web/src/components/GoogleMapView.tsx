'use client';
import {useEffect, useRef, useState} from 'react';
import {loadGoogleMaps, readLocationPermission, shouldShowRealMap, type LocationPermission, type MapSdkState} from '@/lib/googleMaps';
import {MapBackdrop} from './MapBackdrop';

type LatLng = {lat: number; lng: number};

type Props = {
  route?: boolean;
  pulse?: boolean;
  truck?: boolean;
  pickup?: LatLng | null;
  dropoff?: LatLng | null;
  driverLocation?: LatLng | null;
  /** Only wired up where the existing flow lets the user set an address
   *  by hand (the route/quote screen's drop-off). Omit elsewhere. */
  onPick?: (point: LatLng) => void;
};

const MAP_STYLE: google.maps.MapTypeStyle[] = [
  {featureType: 'poi', elementType: 'labels', stylers: [{visibility: 'off'}]},
  {featureType: 'transit', stylers: [{visibility: 'off'}]},
  {featureType: 'landscape', elementType: 'geometry', stylers: [{color: '#ece7dc'}]},
  {featureType: 'water', elementType: 'geometry', stylers: [{color: '#dce5cc'}]},
  {featureType: 'road', elementType: 'geometry', stylers: [{color: '#ffffff'}]},
  {featureType: 'road', elementType: 'labels.icon', stylers: [{visibility: 'off'}]},
];

function pickupIcon(maps: typeof google.maps): google.maps.Symbol {
  return {path: maps.SymbolPath.CIRCLE, scale: 8, fillColor: '#14213d', fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 3};
}
function dropoffIcon(): google.maps.Symbol {
  return {path: 'M -7,-7 L 7,-7 L 7,7 L -7,7 Z', fillColor: '#f2a516', fillOpacity: 1, strokeColor: '#14213d', strokeWeight: 3};
}
function truckIcon(maps: typeof google.maps): google.maps.Symbol {
  return {path: maps.SymbolPath.CIRCLE, scale: 13, fillColor: '#14213d', fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 3};
}

function currentMaps(): typeof google.maps | null {
  return (window as unknown as {google?: {maps?: typeof google.maps}}).google?.maps ?? null;
}

/**
 * Drop-in replacement for `MapBackdrop` on the customer-facing screens: a
 * real, interactive Google Map when a key is configured, the SDK loads,
 * and location permission isn't denied — otherwise the same decorative
 * illustration the app already used, unchanged.
 *
 * Deliberately Maps JavaScript API only (markers + a plain polyline
 * between two points): no Places, Directions, or Geocoding calls, so no
 * address is resolved for a map-clicked point — the caller supplies a
 * generic label for it, the same way it already does for other points.
 */
export function GoogleMapView({route = false, pulse = false, truck = false, pickup, dropoff, driverLocation, onPick}: Props) {
  const hasApiKey = Boolean(process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY);
  const [sdkState, setSdkState] = useState<MapSdkState>('idle');
  const [permission, setPermission] = useState<LocationPermission>('unknown');
  const showMap = shouldShowRealMap({hasApiKey, sdkState, locationPermission: permission});

  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapInstanceRef = useRef<google.maps.Map | null>(null);
  const pickupMarkerRef = useRef<google.maps.Marker | null>(null);
  const dropoffMarkerRef = useRef<google.maps.Marker | null>(null);
  const truckMarkerRef = useRef<google.maps.Marker | null>(null);
  const routeLinesRef = useRef<google.maps.Polyline[]>([]);
  const onPickRef = useRef(onPick);
  useEffect(() => {
    onPickRef.current = onPick;
  });

  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!apiKey) return;
    let cancelled = false;
    readLocationPermission().then(value => {
      if (!cancelled) setPermission(value);
    });
    setSdkState('loading');
    loadGoogleMaps(apiKey)
      .then(() => {
        if (!cancelled) setSdkState('loaded');
      })
      .catch(() => {
        if (!cancelled) setSdkState('error');
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasApiKey]);

  useEffect(() => {
    if (!showMap || !containerRef.current || mapInstanceRef.current) return;
    const maps = currentMaps();
    if (!maps) return;
    const map = new maps.Map(containerRef.current, {
      center: pickup ?? {lat: 47.9186, lng: 106.9177},
      zoom: 14,
      disableDefaultUI: true,
      clickableIcons: false,
      gestureHandling: 'greedy',
      styles: MAP_STYLE,
    });
    mapInstanceRef.current = map;
    map.addListener('click', (event: google.maps.MapMouseEvent) => {
      if (event.latLng) onPickRef.current?.({lat: event.latLng.lat(), lng: event.latLng.lng()});
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showMap]);

  useEffect(() => {
    const map = mapInstanceRef.current;
    const maps = currentMaps();
    if (!map || !maps) return;

    if (pickup) {
      if (!pickupMarkerRef.current) pickupMarkerRef.current = new maps.Marker({map, icon: pickupIcon(maps), zIndex: 2});
      pickupMarkerRef.current.setPosition(pickup);
    } else {
      pickupMarkerRef.current?.setMap(null);
      pickupMarkerRef.current = null;
    }

    if (dropoff) {
      if (!dropoffMarkerRef.current) dropoffMarkerRef.current = new maps.Marker({map, icon: dropoffIcon(), zIndex: 2});
      dropoffMarkerRef.current.setPosition(dropoff);
    } else {
      dropoffMarkerRef.current?.setMap(null);
      dropoffMarkerRef.current = null;
    }

    if (truck && driverLocation) {
      if (!truckMarkerRef.current) truckMarkerRef.current = new maps.Marker({map, icon: truckIcon(maps), zIndex: 3});
      truckMarkerRef.current.setPosition(driverLocation);
    } else {
      truckMarkerRef.current?.setMap(null);
      truckMarkerRef.current = null;
    }

    routeLinesRef.current.forEach(line => line.setMap(null));
    routeLinesRef.current = [];
    if (route && pickup && dropoff) {
      const path = [pickup, dropoff];
      routeLinesRef.current = [
        new maps.Polyline({map, path, strokeColor: '#ffffff', strokeWeight: 9, strokeOpacity: 1, zIndex: 0}),
        new maps.Polyline({map, path, strokeColor: '#14213d', strokeWeight: 5, strokeOpacity: 1, zIndex: 1}),
      ];
    }

    if (pickup && dropoff) {
      const bounds = new maps.LatLngBounds();
      bounds.extend(pickup);
      bounds.extend(dropoff);
      map.fitBounds(bounds, 48);
    } else if (dropoff) {
      map.panTo(dropoff);
    } else if (pickup) {
      map.panTo(pickup);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showMap, pickup?.lat, pickup?.lng, dropoff?.lat, dropoff?.lng, driverLocation?.lat, driverLocation?.lng, route, truck]);

  useEffect(() => {
    return () => {
      pickupMarkerRef.current?.setMap(null);
      dropoffMarkerRef.current?.setMap(null);
      truckMarkerRef.current?.setMap(null);
      routeLinesRef.current.forEach(line => line.setMap(null));
    };
  }, []);

  if (!showMap) return <MapBackdrop route={route} pulse={pulse} truck={truck} />;
  return <div ref={containerRef} className="gmap" aria-label="Газрын зураг" role="application" />;
}
