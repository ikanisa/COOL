function assert(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

const adminRoot = new URL("../", import.meta.url);

Deno.test({
  name: "shared admin data table layer exposes controller and states",
  permissions: { read: true },
  async fn() {
    const controller = await Deno.readTextFile(
      new URL("src/lib/data-table-controller.ts", adminRoot),
    );
    const controls = await Deno.readTextFile(
      new URL("src/components/ui/data-table-controls.tsx", adminRoot),
    );

    for (const token of [
      "export function useDataTableController",
      "setSearch",
      "setFilter",
      "setPage",
      "handleSort",
      "sortData",
      "paginate",
      "exportState",
    ]) {
      assert(
        controller.includes(token),
        `missing data table controller token ${token}`,
      );
    }

    for (const token of [
      "DataTableSearch",
      "DataTableFilterChips",
      "DataTablePagination",
      "DataTableEmptyRow",
    ]) {
      assert(controls.includes(token), `missing shared table control ${token}`);
    }
  },
});

Deno.test({
  name: "high-traffic admin tables use the shared controller",
  permissions: { read: true },
  async fn() {
    for (const file of [
      "src/pages/Users.tsx",
      "src/pages/Members.tsx",
      "src/pages/Groups.tsx",
      "src/pages/Loans.tsx",
      "src/pages/Transactions.tsx",
      "src/pages/Approvals.tsx",
      "src/pages/BioPay.tsx",
      "src/pages/Reconciliation.tsx",
      "src/pages/Health.tsx",
      "src/pages/Settings.tsx",
    ]) {
      const source = await Deno.readTextFile(new URL(file, adminRoot));
      assert(
        source.includes("useDataTableController"),
        `${file} must use shared table state`,
      );
      assert(
        !source.includes("const [search, setSearch]"),
        `${file} must not own duplicate search state`,
      );
      assert(
        !source.includes("const [page, setPage]"),
        `${file} must not own duplicate pagination state`,
      );
    }
  },
});
