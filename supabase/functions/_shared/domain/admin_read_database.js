// A managed Admin read is assembled as a batch so every statement runs under
// the same live session and grant check. Prepared values cannot execute alone.
export function createAdminReadDatabase(database, context, authorityCheck, handleError) {
  const prepared = new WeakMap();

  function describe(statement) {
    const descriptor = Object.freeze({
      bind: (...values) => describe(statement.bind(...values)),
    });
    prepared.set(descriptor, statement);
    return descriptor;
  }

  return Object.freeze({
    prepare: (sql) => describe(database.prepare(sql)),
    async batch(descriptors) {
      const statements = descriptors.map((descriptor) => {
        const statement = prepared.get(descriptor);
        if (!statement) throw new TypeError('Expected a statement prepared in this Admin read scope.');
        return statement;
      });
      try {
        return await database.adminReadBatch(context, authorityCheck, statements);
      } catch (error) {
        return handleError(error);
      }
    },
  });
}
