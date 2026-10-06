export function placeName(result: Record<string, unknown>): string | null {
  // A nearest street address can describe a different building from the
  // photograph. Use the broader locality, and let the user edit the result.
  const locality = [
    result.city,
    result.town,
    result.village,
    result.municipality,
    result.county,
  ].find((value) => typeof value === 'string' && value.trim() !== '');
  const parts = [locality, result.state, result.country]
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
