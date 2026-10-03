export function assertEquals(actual: unknown, expected: unknown): void {
  if (Object.is(actual, expected)) return;
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson === expectedJson) return;
  throw new Error(`Expected ${expectedJson}, received ${actualJson}`);
}
