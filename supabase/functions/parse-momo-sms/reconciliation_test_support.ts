type TableRow = Record<string, unknown>;
export type TableStore = Record<string, TableRow[]>;
type QueryResult = { data: unknown; error: unknown | null };
type RpcCall = { name: string; args: Record<string, unknown> | undefined };

export function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

export function assertEquals<T>(
  actual: T,
  expected: T,
  message: string,
): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

export function assertDeepEquals(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${message}: expected ${expectedJson}, got ${actualJson}`);
  }
}

export class FakeAdminClient {
  readonly rpcCalls: RpcCall[] = [];

  constructor(
    private readonly tables: TableStore,
    private readonly options: {
      rpcFailures?: Record<string, string>;
    } = {},
  ) {}

  from(table: string): FakeQueryBuilder {
    return new FakeQueryBuilder(this.tables, table);
  }

  rpc(name: string, args?: Record<string, unknown>): Promise<QueryResult> {
    this.rpcCalls.push({ name, args });
    const failureMessage = this.options.rpcFailures?.[name];
    if (failureMessage) {
      return Promise.resolve({
        data: null,
        error: new Error(failureMessage),
      });
    }

    if (name === "confirm_contribution") {
      const contributionId = typeof args?.p_contribution_id === "string"
        ? args.p_contribution_id
        : null;
      const contributions = this.tables.group_contributions ?? [];
      const contribution = contributionId
        ? contributions.find((row) => row.id === contributionId)
        : null;

      if (!contribution) {
        return Promise.resolve({
          data: {
            status: "error",
            message: "Contribution not found",
          },
          error: null,
        });
      }

      const normalizedStatus = String(contribution.status ?? "")
        .trim()
        .toLowerCase();
      if (normalizedStatus !== "confirmed") {
        contribution.status = "confirmed";
        contribution.confirmed_at = contribution.confirmed_at ??
          new Date().toISOString();

        const groupId = typeof contribution.group_id === "string"
          ? contribution.group_id
          : null;
        const amount = typeof contribution.amount === "number"
          ? contribution.amount
          : Number(contribution.amount ?? 0);
        const group = groupId
          ? (this.tables.groups ?? []).find((row) => row.id === groupId)
          : null;
        if (group) {
          const currentAmount = typeof group.amount === "number"
            ? group.amount
            : Number(group.amount ?? 0);
          group.amount = currentAmount + amount;
        }
      }

      return Promise.resolve({
        data: {
          status: normalizedStatus === "confirmed" ? "already_confirmed" : "ok",
        },
        error: null,
      });
    }

    return Promise.resolve({ data: null, error: null });
  }
}

class FakeQueryBuilder implements PromiseLike<QueryResult> {
  private action: "select" | "update" | "insert" = "select";
  private filters: Array<
    | { kind: "eq"; column: string; value: unknown }
    | { kind: "in"; column: string; values: unknown[] }
    | { kind: "ilike"; column: string; value: string }
  > = [];
  private limitCount: number | null = null;
  private orderColumn: string | null = null;
  private ascending = true;
  private updatePayload: Record<string, unknown> | null = null;
  private insertPayload: Record<string, unknown>[] = [];
  private insertedRows: TableRow[] | null = null;

  constructor(
    private readonly tables: TableStore,
    private readonly table: string,
  ) {}

  select(_columns: string): this {
    if (this.action !== "insert") {
      this.action = "select";
    }
    return this;
  }

  update(values: Record<string, unknown>): this {
    this.action = "update";
    this.updatePayload = values;
    return this;
  }

  insert(values: Record<string, unknown> | Record<string, unknown>[]): this {
    this.action = "insert";
    this.insertPayload = Array.isArray(values) ? values : [values];
    return this;
  }

  eq(column: string, value: unknown): this {
    this.filters.push({ kind: "eq", column, value });
    return this;
  }

  in(column: string, values: unknown[]): this {
    this.filters.push({ kind: "in", column, values });
    return this;
  }

  ilike(column: string, value: string): this {
    this.filters.push({ kind: "ilike", column, value });
    return this;
  }

  order(column: string, options?: { ascending?: boolean }): this {
    this.orderColumn = column;
    this.ascending = options?.ascending ?? true;
    return this;
  }

  limit(count: number): this {
    this.limitCount = count;
    return this;
  }

  maybeSingle(): Promise<QueryResult> {
    return Promise.resolve(this.execute(true));
  }

  single(): Promise<QueryResult> {
    return Promise.resolve(this.execute(true));
  }

  then<TResult1 = QueryResult, TResult2 = never>(
    onfulfilled?:
      | ((value: QueryResult) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?:
      | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
      | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this.execute(false)).then(onfulfilled, onrejected);
  }

  private execute(expectSingle: boolean): QueryResult {
    if (this.action === "insert") {
      if (this.insertedRows == null) {
        const target = this.tables[this.table] ??= [];
        this.insertedRows = this.insertPayload.map((row, index) => {
          const payload = { ...row };
          payload.id ??= `${this.table}-${target.length + index + 1}`;
          return payload;
        });
        target.push(...this.insertedRows);
      }

      const limitedInserted = this.limitCount == null
        ? this.insertedRows
        : this.insertedRows.slice(0, this.limitCount);
      return {
        data: expectSingle ? (limitedInserted[0] ?? null) : limitedInserted,
        error: null,
      };
    }

    const rows = [...(this.tables[this.table] ?? [])].filter((row) =>
      this.matches(row)
    );

    if (this.orderColumn) {
      rows.sort((left, right) => {
        const leftValue = String(left[this.orderColumn!] ?? "");
        const rightValue = String(right[this.orderColumn!] ?? "");
        return this.ascending
          ? leftValue.localeCompare(rightValue)
          : rightValue.localeCompare(leftValue);
      });
    }

    const limitedRows = this.limitCount == null
      ? rows
      : rows.slice(0, this.limitCount);

    if (this.action === "update") {
      for (const row of limitedRows) {
        Object.assign(row, this.updatePayload);
      }
      return { data: limitedRows, error: null };
    }

    return {
      data: expectSingle ? (limitedRows[0] ?? null) : limitedRows,
      error: null,
    };
  }

  private matches(row: TableRow): boolean {
    return this.filters.every((filter) => {
      const value = row[filter.column];
      switch (filter.kind) {
        case "eq":
          return value === filter.value;
        case "in":
          return filter.values.includes(value);
        case "ilike":
          return String(value ?? "").toLowerCase().includes(
            filter.value.replaceAll("%", "").toLowerCase(),
          );
      }
    });
  }
}
