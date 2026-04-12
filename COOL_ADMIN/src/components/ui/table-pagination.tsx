import * as React from "react";
import { Button } from "@/components/ui/button";

interface TablePaginationProps {
  totalItems: number;
  defaultPageSize?: number;
}

export function TablePagination({ totalItems, defaultPageSize = 100 }: TablePaginationProps) {
  const [pageSize, setPageSize] = React.useState(defaultPageSize);

  return (
    <div className="flex flex-col sm:flex-row items-center justify-between p-4 border-t border-zinc-100 text-sm text-zinc-500 gap-4">
      <div className="flex flex-col sm:flex-row items-center gap-4 w-full sm:w-auto">
        <div>
          Showing 1 to {Math.min(pageSize, totalItems)} of {totalItems.toLocaleString()} entries
        </div>
        <div className="flex items-center gap-2">
          <span>Rows per page:</span>
          <select 
            className="h-8 rounded-md border border-zinc-200 bg-white px-2 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 text-zinc-900 font-medium"
            value={pageSize}
            onChange={(e) => setPageSize(Number(e.target.value))}
          >
            <option value={100}>100</option>
            <option value={500}>500</option>
            <option value={1000}>1000</option>
          </select>
        </div>
      </div>
      <div className="flex items-center gap-2 w-full sm:w-auto justify-end">
        <Button variant="outline" size="sm" disabled>Previous</Button>
        <Button variant="outline" size="sm">Next</Button>
      </div>
    </div>
  );
}
