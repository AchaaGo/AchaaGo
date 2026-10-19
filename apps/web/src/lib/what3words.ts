import type {Point} from './api';

export type AddressMethod = 'google' | 'what3words';
export type WordSuggestion = {words:string; nearestPlace:string; country:string};

// Accept Cyrillic/Latin and other Unicode words, with optional /// and dot variants.
// This is format validation only: existence and coordinates come from the API.
export function normalizeWords(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 150) return null;
  const words = value.trim().replace(/^\/\/\/\s*/, '').normalize('NFC').toLowerCase()
    .replace(/[｡。･・︒។։။۔።।]/g,'.').split('.').map(word => word.trim());
  return words.length === 3 && words.every(word => /^[\p{L}\p{M}]+(?:[-'’][\p{L}\p{M}]+)*$/u.test(word)) ? words.join('.') : null;
}

export function pointFromWords(data: {words?:unknown; coordinates?:{lat?:unknown; lng?:unknown}}): Point | null {
  const words = normalizeWords(data.words), lat = data.coordinates?.lat, lng = data.coordinates?.lng;
  return words && typeof lat === 'number' && Number.isFinite(lat) && Math.abs(lat) <= 90
    && typeof lng === 'number' && Number.isFinite(lng) && Math.abs(lng) <= 180
    ? {lat,lng,address:`///${words}`} : null;
}
