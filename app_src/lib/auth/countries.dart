/// Country names by code, for the country picker and for statistics.
const Map<String, String> countryNames = {
  'DZ': 'Algeria',
  'AO': 'Angola',
  'AU': 'Australia',
  'BR': 'Brazil',
  'CM': 'Cameroon',
  'CA': 'Canada',
  'CD': 'DR Congo',
  'EG': 'Egypt',
  'ET': 'Ethiopia',
  'FR': 'France',
  'DE': 'Germany',
  'GH': 'Ghana',
  'IN': 'India',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IT': 'Italy',
  'CI': 'Ivory Coast',
  'JP': 'Japan',
  'KE': 'Kenya',
  'MX': 'Mexico',
  'MA': 'Morocco',
  'MZ': 'Mozambique',
  'NL': 'Netherlands',
  'NG': 'Nigeria',
  'PK': 'Pakistan',
  'PH': 'Philippines',
  'RW': 'Rwanda',
  'SA': 'Saudi Arabia',
  'SN': 'Senegal',
  'ZA': 'South Africa',
  'ES': 'Spain',
  'TZ': 'Tanzania',
  'TR': 'Turkey',
  'UG': 'Uganda',
  'AE': 'United Arab Emirates',
  'GB': 'United Kingdom',
  'US': 'United States',
  'ZM': 'Zambia',
  'ZW': 'Zimbabwe',
};

String countryName(String code) {
  if (code == 'OTHER') return 'Other';
  if (code == 'ZZ') return 'Unknown';
  return countryNames[code.toUpperCase()] ?? code;
}
