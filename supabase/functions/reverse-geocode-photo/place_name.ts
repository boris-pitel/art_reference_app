export function placeName(result: Record<string, unknown>): string | null {
  const text = (value: unknown): string =>
    typeof value === 'string' ? value.trim() : '';
  const countryName = text(result.country);
  const countryCode = text(result.country_code).toUpperCase();
  const country = countryCode === 'US' || /^(united states( of america)?|usa)$/i.test(countryName)
    ? 'USA'
    : countryCode === 'GB' || /^(united kingdom|united kingdom of great britain and northern ireland)$/i.test(countryName)
    ? 'UK'
    : countryCode === 'AE' || /^united arab emirates$/i.test(countryName)
    ? 'UAE'
    : countryName || countryCode;
  const stateName = text(result.state);
  // Use the provider's regional abbreviation; retain the name if unavailable.
  const rawStateCode = text(result.state_code);
  const state = (countryCode && rawStateCode.toUpperCase().startsWith(`${countryCode}-`)
    ? rawStateCode.slice(countryCode.length + 1)
    : rawStateCode) || stateName;
  // Keep the provider's local street/house-number order, but compose the
  // locality ourselves so a full formatted address cannot bypass abbreviations.
  const street = text(result.street);
  const formatted = text(result.formatted);
  const addressLine = text(result.address_line1);
  const formattedStreet = formatted.split(',')[0].trim();
  const address = street
    ? addressLine.toLowerCase().includes(street.toLowerCase())
      ? addressLine
      : formattedStreet.toLowerCase().includes(street.toLowerCase())
      ? formattedStreet
      : [text(result.housenumber), street].filter(Boolean).join(' ')
    : addressLine;
  const locality = [
    result.city,
    result.town,
    result.village,
    result.municipality,
    result.county,
  ].find((value) => typeof value === 'string' && value.trim() !== '');
  const parts = [address, locality, state, result.postcode, country]
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
