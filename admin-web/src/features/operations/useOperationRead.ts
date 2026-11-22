import {useCallback, useEffect, useRef, useState} from 'react';
import {AdminRequestError} from '../../api/client';

export type OperationReadState<T> =
  | {key: string; status: 'success'; value: T; receivedAt: number}
  | {key: string; status: 'error'; message: string};

/** Coalesce a single in-flight read across React's development effect replay. */
export function useOperationRead<T>(
  key: string,
  enabled: boolean,
  load: () => Promise<T>,
  {pollMs, invalidResponse = 'The workspace response could not be verified.'}: {pollMs?: number; invalidResponse?: string} = {},
) {
  const [result, setResult] = useState<OperationReadState<T> | null>(null);
  const [attempt, setAttempt] = useState(0);
  const flight = useRef<{key: string; promise: Promise<T>} | null>(null);
  const attemptKey = `${key}:${attempt}`;

  useEffect(() => {
    if (!enabled) return;
    let read = flight.current;
    if (!read || read.key !== attemptKey) {
      read = {key: attemptKey, promise: load()};
      flight.current = read;
    }
    const current = read;
    let active = true;
    current.promise.then(value => {
      if (active) setResult({key: attemptKey, status: 'success', value, receivedAt: Date.now() / 1000});
    }, (error: unknown) => {
      if (active) {
        setResult({
          key: attemptKey, status: 'error',
          message: error instanceof AdminRequestError ? error.message : invalidResponse,
        });
      }
    }).finally(() => {
      if (flight.current === current) flight.current = null;
    });
    return () => {active = false;};
  }, [attemptKey, enabled, invalidResponse, load]);

  const retry = useCallback(() => {
    if (!pollMs || !flight.current) setAttempt(value => value + 1);
  }, [pollMs]);

  useEffect(() => {
    if (!enabled || !pollMs) return;
    const refreshVisible = () => {
      if (document.visibilityState === 'visible' && navigator.onLine) retry();
    };
    const timer = window.setInterval(refreshVisible, pollMs);
    document.addEventListener('visibilitychange', refreshVisible);
    window.addEventListener('focus', refreshVisible);
    window.addEventListener('online', refreshVisible);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', refreshVisible);
      window.removeEventListener('focus', refreshVisible);
      window.removeEventListener('online', refreshVisible);
    };
  }, [enabled, pollMs, retry]);

  return {result: enabled && result?.key === attemptKey ? result : null, retry};
}
