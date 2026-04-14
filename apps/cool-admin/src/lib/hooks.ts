import { useState, useEffect, useCallback } from "react";

interface UseAsyncDataResult<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

interface UseAsyncDataOptions {
  refreshIntervalMs?: number;
}

/**
 * Generic hook for async data fetching with loading/error/refetch states.
 * Avoids duplicating the same pattern on every page.
 */
export function useAsyncData<T>(
  fetcher: () => Promise<T>,
  deps: unknown[] = [],
  options: UseAsyncDataOptions = {}
): UseAsyncDataResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await fetcher();
      setData(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    fetch();
  }, [fetch]);

  useEffect(() => {
    if (!options.refreshIntervalMs || options.refreshIntervalMs <= 0) {
      return;
    }

    const handle = window.setInterval(() => {
      void fetch();
    }, options.refreshIntervalMs);

    return () => window.clearInterval(handle);
  }, [fetch, options.refreshIntervalMs]);

  return { data, loading, error, refetch: fetch };
}
