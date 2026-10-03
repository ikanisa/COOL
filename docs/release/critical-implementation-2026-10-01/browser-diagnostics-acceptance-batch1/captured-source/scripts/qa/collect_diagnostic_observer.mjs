// Observe the fixed CollectDiagnostics boundary at any browser console level.
// Invalid declarations fail without retaining arbitrary text or caller fields.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {relative} from 'node:path';
import {fileURLToPath} from 'node:url';

const severities = Object.freeze({
  startupStarted: 'info', startupWaiting: 'info', startupReady: 'info',
  startupTimedOut: 'warning', diagnosticsSuppressed: 'warning',
  startupFailed: 'error', frameworkFailure: 'error', platformFailure: 'error',
});
const fields = ['collect_diagnostic', 'code', 'severity', 'surface', 'environment',
  'build_version', 'attempt', 'elapsed_ms'].sort();
const invalid = reason => ({failure: true, reason, event: null});
const own = (value, key) => Object.hasOwn(value, key);

export function classifyCollectDiagnostic(text) {
  if (typeof text !== 'string') return null;
  const declared = /"collect_diagnostic"\s*:/.test(text);
  if (text.length > 1024) return declared ? invalid('oversized_collect_diagnostic') : null;
  let event;
  try { event = JSON.parse(text); }
  catch { return declared ? invalid('malformed_collect_diagnostic') : null; }
  if (!event || typeof event !== 'object' || Array.isArray(event) || !own(event, 'collect_diagnostic')) {
    return declared ? invalid('invalid_collect_diagnostic_contract') : null;
  }
  // JSON.parse silently accepts duplicate keys. The fixed flat primitive
  // contract cannot contain property-looking nested data or free text, so
  // lexical key counts must match the eight unique decoded field names too.
  let lexicalKeys;
  try {
    lexicalKeys = [...text.matchAll(/"((?:\\.|[^"\\])*)"\s*:/g)]
      .map(match => JSON.parse('"' + match[1] + '"'));
  } catch { return invalid('invalid_collect_diagnostic_contract'); }
  if (lexicalKeys.length !== fields.length || new Set(lexicalKeys).size !== fields.length ||
      JSON.stringify(Object.keys(event).sort()) !== JSON.stringify(fields) ||
      event.collect_diagnostic !== 1 || typeof event.code !== 'string' || !own(severities, event.code) ||
      event.severity !== severities[event.code] ||
      !['member', 'admin'].includes(event.surface) ||
      !['local', 'development', 'staging', 'production', 'unknown'].includes(event.environment) ||
      typeof event.build_version !== 'string' || event.build_version.length > 32 ||
      !(event.build_version === 'unknown' || /^\d+\.\d+\.\d+(?:\+\d+)?$/.exec(event.build_version)?.[0] === event.build_version) ||
      !Number.isSafeInteger(event.attempt) || event.attempt < 1 || event.attempt > 1000 ||
      !Number.isSafeInteger(event.elapsed_ms) || event.elapsed_ms < 0 || event.elapsed_ms > 86400000) {
    return invalid('invalid_collect_diagnostic_contract');
  }
  return {failure: event.severity !== 'info',
    reason: event.severity === 'info' ? 'observed_info' : 'collect_application_failure', event};
}

export function observeCollectDiagnostics(page, onFailure) {
  const handler = message => {
    const observation = classifyCollectDiagnostic(message.text());
    if (observation?.failure) onFailure(observation);
  };
  page.on('console', handler);
  return () => page.off('console', handler);
}

export function collectDiagnosticFailures(logs) {
  return logs.flatMap(entry => {
    const observation = classifyCollectDiagnostic(entry.text);
    return observation?.failure ? [observation] : [];
  });
}

export function sanitizeCollectDiagnosticLog(entry) {
  const diagnostic = classifyCollectDiagnostic(entry.text);
  if (!diagnostic) return entry;
  const level = ['log', 'info', 'debug', 'error', 'assert', 'warn', 'warning'].includes(entry.level)
    ? entry.level : 'unknown';
  return {level, text: 'Collect diagnostic observation', diagnostic};
}

export async function collectDiagnosticSourceSnapshot(recorderUrl) {
  const root = fileURLToPath(new URL('../..', import.meta.url));
  const snapshot = {};
  for (const url of [new URL(import.meta.url), new URL(recorderUrl)]) {
    const path = relative(root, fileURLToPath(url)).replaceAll('\\', '/');
    if (!path.startsWith('scripts/') || !path.endsWith('.mjs')) throw Error('Diagnostic recorder must be a repository script');
    snapshot[path] = createHash('sha256').update(await readFile(url)).digest('hex');
  }
  return snapshot;
}
