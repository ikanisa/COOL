export interface AdminSearchOptions {
  minLength?: number;
  maxLength?: number;
}

const ADMIN_SEARCH_COLUMN_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;

export function normalizeAdminSearchTerm(
  search: string,
  options: AdminSearchOptions = {},
): string | null {
  const minLength = options.minLength ?? 1;
  const maxLength = options.maxLength ?? 64;
  const normalized = search
    .normalize("NFKC")
    .trim()
    .replace(/[^\p{L}\p{N}\s+-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength)
    .trim();

  return normalized.length >= minLength ? normalized : null;
}

export function buildAdminIlikeOrFilter(
  search: string,
  columns: string[],
  options: AdminSearchOptions = {},
): string | null {
  const normalized = normalizeAdminSearchTerm(search, options);
  if (!normalized) return null;
  for (const column of columns) {
    if (!ADMIN_SEARCH_COLUMN_PATTERN.test(column)) {
      throw new Error(`Unsupported admin search column: ${column}`);
    }
  }
  return columns.map((column) => `${column}.ilike.%${normalized}%`).join(",");
}
