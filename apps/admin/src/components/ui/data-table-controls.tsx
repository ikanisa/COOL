import type { ReactNode } from "react";
import { Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { TableCell, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";

export interface DataTableFilterOption<TValue extends string | null = string | null> {
  value: TValue;
  label: string;
  count?: number;
}

interface DataTableSearchProps {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  className?: string;
}

export function DataTableSearch({
  value,
  onChange,
  placeholder,
  className,
}: DataTableSearchProps) {
  return (
    <div className={cn("relative w-full sm:w-80", className)}>
      <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-400" />
      <Input
        className="pl-9"
        placeholder={placeholder}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </div>
  );
}

interface DataTableToolbarProps {
  children: ReactNode;
  trailing?: ReactNode;
  className?: string;
}

export function DataTableToolbar({
  children,
  trailing,
  className,
}: DataTableToolbarProps) {
  return (
    <div
      className={cn(
        "flex flex-col gap-4 border-b border-zinc-100 p-4 sm:flex-row sm:items-center sm:justify-between",
        className
      )}
    >
      <div className="flex w-full min-w-0 flex-col gap-3 sm:w-auto sm:flex-row sm:items-center">
        {children}
      </div>
      {trailing && <div className="flex min-w-0 items-center gap-2 overflow-x-auto pb-1 sm:pb-0">{trailing}</div>}
    </div>
  );
}

interface DataTableFilterChipsProps<TValue extends string | null = string | null> {
  value: TValue;
  options: Array<DataTableFilterOption<TValue>>;
  onChange: (value: TValue) => void;
}

export function DataTableFilterChips<TValue extends string | null = string | null>({
  value,
  options,
  onChange,
}: DataTableFilterChipsProps<TValue>) {
  return (
    <>
      {options.map((option) => {
        const selected = value === option.value;
        return (
          <Badge
            key={option.value ?? "all"}
            variant={selected ? "secondary" : "outline"}
            className={cn(
              "cursor-pointer whitespace-nowrap",
              selected ? "bg-indigo-50 text-indigo-700" : "hover:bg-zinc-50"
            )}
            onClick={() => onChange(option.value)}
          >
            {option.label}
            {option.count !== undefined && (
              <span className="ml-1 text-[10px] opacity-70">{option.count}</span>
            )}
          </Badge>
        );
      })}
    </>
  );
}

interface DataTablePaginationProps {
  page: number;
  pageSize: number;
  total: number;
  onPageChange: (page: number) => void;
}

export function DataTablePagination({
  page,
  pageSize,
  total,
  onPageChange,
}: DataTablePaginationProps) {
  const start = total === 0 ? 0 : page * pageSize + 1;
  const end = Math.min((page + 1) * pageSize, total);
  const canGoBack = page > 0;
  const canGoForward = (page + 1) * pageSize < total;

  return (
    <div className="flex flex-col gap-3 border-t border-zinc-100 p-4 sm:flex-row sm:items-center sm:justify-between">
      <p className="text-sm text-zinc-500">
        Showing {start}–{end} of {total}
      </p>
      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          disabled={!canGoBack}
          onClick={() => onPageChange(page - 1)}
        >
          Previous
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={!canGoForward}
          onClick={() => onPageChange(page + 1)}
        >
          Next
        </Button>
      </div>
    </div>
  );
}

interface DataTableEmptyRowProps {
  colSpan: number;
  icon?: ReactNode;
  message: string;
}

export function DataTableEmptyRow({
  colSpan,
  icon,
  message,
}: DataTableEmptyRowProps) {
  return (
    <TableRow>
      <TableCell colSpan={colSpan} className="h-32 text-center">
        <div className="flex flex-col items-center gap-2 text-zinc-400">
          {icon}
          <p className="text-sm">{message}</p>
        </div>
      </TableCell>
    </TableRow>
  );
}
