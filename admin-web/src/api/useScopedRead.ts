import {useEffect, useState} from 'react';

interface ReadResult<T> {
  scope: string;
  value: T | null;
  failed: boolean;
}

/** Publish a read only for the authority, selection and refresh that issued it. */
export function useScopedRead<T>(enabled: boolean, key: string, load: (signal: AbortSignal) => Promise<T>) {
  const [result, setResult] = useState<ReadResult<T> | null>(null);
  const [revision, setRevision] = useState(0);
  const scope = JSON.stringify([key, revision]);

  useEffect(() => {
    if (!enabled) return;
    const controller = new AbortController();
    const {signal} = controller;
    void load(signal).then(value => {
      if (!signal.aborted) setResult({scope, value, failed: false});
    }, () => {
      if (!signal.aborted) setResult({scope, value: null, failed: true});
    });
    return () => controller.abort();
  }, [enabled, load, scope]);

  return {
    result: enabled && result?.scope === scope ? result : null,
    refresh: () => setRevision(value => value + 1),
  };
}
