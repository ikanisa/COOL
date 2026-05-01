import { useCallback, useMemo, useState } from "react";

export type DataTableFilterValue = string | null;
export type DataTableSortDirection = "asc" | "desc" | null;

interface UseDataTableControllerOptions<TFilter extends DataTableFilterValue> {
  pageSize: number;
  initialPage?: number;
  initialSearch?: string;
  initialFilter?: TFilter;
  initialSortKey?: string | null;
  initialSortDirection?: DataTableSortDirection;
}

export function useDataTableController<
  TFilter extends DataTableFilterValue = DataTableFilterValue,
>({
  pageSize,
  initialPage = 0,
  initialSearch = "",
  initialFilter = null as TFilter,
  initialSortKey = null,
  initialSortDirection = null,
}: UseDataTableControllerOptions<TFilter>) {
  const [page, setPage] = useState(initialPage);
  const [search, setSearchValue] = useState(initialSearch);
  const [filter, setFilterValue] = useState<TFilter>(initialFilter);
  const [sortKey, setSortKey] = useState<string | null>(initialSortKey);
  const [sortDirection, setSortDirection] =
    useState<DataTableSortDirection>(initialSortDirection);

  const setSearch = useCallback((value: string) => {
    setSearchValue(value);
    setPage(0);
  }, []);

  const setFilter = useCallback((value: TFilter) => {
    setFilterValue(value);
    setPage(0);
  }, []);

  const handleSort = useCallback(
    (key: string) => {
      if (!key) return;

      setPage(0);
      if (sortKey !== key) {
        setSortKey(key);
        setSortDirection("desc");
        return;
      }

      const nextDirection: DataTableSortDirection =
        sortDirection === "asc"
          ? "desc"
          : sortDirection === "desc"
            ? null
            : "asc";

      setSortDirection(nextDirection);
      setSortKey(nextDirection ? key : null);
    },
    [sortDirection, sortKey],
  );

  const sortData = useCallback(
    <TRow extends Record<string, unknown>>(rows: TRow[]): TRow[] => {
      if (!sortKey || !sortDirection) return rows;

      return [...rows].sort((a, b) => {
        const aValue = a[sortKey];
        const bValue = b[sortKey];

        if (aValue === bValue) return 0;
        if (aValue === null || aValue === undefined) return 1;
        if (bValue === null || bValue === undefined) return -1;

        const comparison =
          typeof aValue === "number" && typeof bValue === "number"
            ? aValue - bValue
            : String(aValue).localeCompare(String(bValue));

        return sortDirection === "asc" ? comparison : -comparison;
      });
    },
    [sortDirection, sortKey],
  );

  const paginate = useCallback(
    <TRow,>(rows: TRow[]): TRow[] =>
      rows.slice(page * pageSize, (page + 1) * pageSize),
    [page, pageSize],
  );

  const reset = useCallback(() => {
    setPage(initialPage);
    setSearchValue(initialSearch);
    setFilterValue(initialFilter);
    setSortKey(initialSortKey);
    setSortDirection(initialSortDirection);
  }, [
    initialFilter,
    initialPage,
    initialSearch,
    initialSortDirection,
    initialSortKey,
  ]);

  const exportState = useMemo(
    () => ({
      page,
      pageSize,
      search: search.trim(),
      filter,
      sortKey,
      sortDirection,
    }),
    [filter, page, pageSize, search, sortDirection, sortKey],
  );

  return {
    page,
    pageSize,
    search,
    filter,
    sortKey,
    sortDirection,
    setPage,
    setSearch,
    setFilter,
    handleSort,
    sortData,
    paginate,
    reset,
    exportState,
  };
}
