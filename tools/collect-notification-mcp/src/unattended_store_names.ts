const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
export const unattendedBasenamePattern = new RegExp(`^(?:${UUID}\\.(?:checkpoint|armed|outcome|lookup|run|step|closed)\\.json|principal-${UUID}\\.lock\\.json|principal-${UUID}\\.history-[0-9]{10}\\.json)$`);
export function validUnattendedBasename(value: unknown): value is string {
  return typeof value === "string" && value.length <= 128 && unattendedBasenamePattern.test(value);
}
