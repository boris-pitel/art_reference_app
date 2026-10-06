export function placeName(result: Record<string, unknown>): string | null {
  const text = (value: unknown): string =>
    typeof value === 'string' ? value.trim() : '';
  // Preserve the provider's local address ordering when a street is known.
  const street = text(result.street);
  const formatted = text(result.formatted);
  if (street && formatted) return formatted.slice(0, 200);
  const address = street
    ? [text(result.housenumber), street].filter(Boolean).join(' ')
    : text(result.address_line1);
  const locality = [
    result.city,
    result.town,
    result.village,
    result.municipality,
    result.county,
  ].find((value) => typeof value === 'string' && value.trim() !== '');
  const parts = [address, locality, result.state, result.country]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => value.trim())
    .filter((value) => value !== '');
  const unique = parts.filter((value, index) =>
    parts.findIndex((other) => other.toLowerCase() === value.toLowerCase()) ===
      index
  );
  const name = unique.join(', ');
  return name ? name.slice(0, 200) : null;
}
