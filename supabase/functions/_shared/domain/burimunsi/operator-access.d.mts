// Generated from contracts/burimunsi-api/{schema,operator-access}.json.
export type OperatorCapability = "records.read" | "members.enroll" | "payments.allocate" | "staff.manage" | "sms.read" | "gateway.manage";
export const REQUIRED_CAPABILITY: "records.read";
export const CAPABILITIES: readonly OperatorCapability[];
export function roleAllowsCapability(role: unknown, capability: unknown): boolean;
export function validOperatorCapabilities(role: unknown, values: unknown): values is OperatorCapability[];
