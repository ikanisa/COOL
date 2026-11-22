import {
  DesktopError, validate, PREPARE_SCHEMA, EMPTY_SCHEMA, EXECUTE_SCHEMA, ATTEMPT_SCHEMA, RECONCILE_SCHEMA,
  STOP_SCHEMA, EXCEPTIONS_SCHEMA,
} from './contract.mjs';
function tool(name, method, title, description, inputSchema, readOnlyHint = false) {
  const definition = {
    name, title, description, inputSchema,
    annotations: {
      readOnlyHint,
      destructiveHint: false,
      idempotentHint: readOnlyHint,
      openWorldHint: !['operator_health', 'prepare_notification', 'get_pending_exceptions', 'stop_all'].includes(name),
    },
  };
  return [name, { definition, method }];
}

const tools = new Map([
  tool('operator_health', 'health', 'Desktop operator health', 'Inspect local policy and native capability availability. Dry mode does not prove native dispatch.', EMPTY_SCHEMA, true),
  tool('observe_admin_queue', 'observeAdminQueue', 'Observe visible Admin queue', 'Request visible desktop queue observation. Returns unavailable when no native adapter is configured.', EMPTY_SCHEMA, true),
  tool('prepare_notification', 'prepareNotification', 'Prepare notification', 'Prepare a source-derived payment receipt with visible recipient and authority checks. Does not dispatch.', PREPARE_SCHEMA),
  tool('dispatch_prepared_notification', 'dispatchPreparedNotification', 'Dispatch prepared notification', 'Request one fenced native dispatch of an existing ticket. Dry mode blocks sending; uncertainty never authorizes replay.', EXECUTE_SCHEMA),
  tool('reconcile_attempt', 'reconcileAttempt', 'Reconcile attempt', 'Request native observation of an existing attempt without resending it. Optional lease recovery requires trusted quiescence verification; caller fields do not establish recovery.', RECONCILE_SCHEMA),
  tool('write_admin_outcome', 'writeAdminOutcome', 'Write visible Admin outcome', 'Request visible UI writeback for an existing attempt. Returns unavailable when no native adapter is configured.', ATTEMPT_SCHEMA),
  tool('prepare_call', 'prepareCall', 'Prepare call', 'Calling is unavailable. No native call lifecycle is configured.', EMPTY_SCHEMA),
  tool('start_prepared_call', 'startPreparedCall', 'Start prepared call', 'Calling is unavailable. Does not dial.', EMPTY_SCHEMA),
  tool('inspect_call_state', 'inspectCallState', 'Inspect call state', 'Call observation is unavailable without a verified native call lifecycle.', EMPTY_SCHEMA, true),
  tool('end_current_call', 'endCurrentCall', 'End current call', 'Call control is unavailable without a verified native call lifecycle.', EMPTY_SCHEMA),
  tool('get_pending_exceptions', 'getPendingExceptions', 'Pending desktop exceptions', 'Read a bounded page of local journal exceptions.', EXCEPTIONS_SCHEMA, true),
  tool('stop_all', 'stopAll', 'Stop desktop operations', 'Persist the stop gate immediately, including while a native dispatch is in progress.', STOP_SCHEMA),
]);

export const DESKTOP_TOOLS = Object.freeze(Array.from(tools.values(), ({ definition }) => definition));

export async function callDesktopTool(core, name, args = {}, signal) {
  const tool = tools.get(name);
  if (!tool) {
    throw new DesktopError('invalid_arguments', 'The tool arguments are invalid. Use the published tool schema.');
  }
  const input = validate(tool.definition.inputSchema, args);
  if (signal?.aborted) throw new DesktopError('cancelled', 'The desktop action was cancelled. No action was retried.');
  if (name === 'operator_health') return core.health();
  return core[tool.method](input, signal);
}
