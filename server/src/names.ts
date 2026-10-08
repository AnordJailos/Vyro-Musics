/** "Nova  Wave!" and "nova-wave" give the same key, so look-alike artist names cannot both exist. */
export function normalizeName(name: string): string {
  return name
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '');
}
