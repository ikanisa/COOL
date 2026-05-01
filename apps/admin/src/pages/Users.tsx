import { useState } from "react";
import { Link } from "react-router-dom";
import { Plus, MoreHorizontal, Eye, Loader2, RefreshCw, AlertTriangle, Users as UsersIcon, Download, FileSpreadsheet } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  DataTableEmptyRow,
  DataTablePagination,
  DataTableSearch,
  DataTableToolbar,
} from "@/components/ui/data-table-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DetailSheet, DetailSection, DetailRow } from "@/components/ui/detail-sheet";
import { useDataTableController } from "@/lib/data-table-controller";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";
import { listAdminUsers, type AdminUserRow } from "@/lib/api/admin-users";

const PAGE_SIZE = 20;

export function UsersList() {
  const table = useDataTableController({ pageSize: PAGE_SIZE });
  const [selectedUser, setSelectedUser] = useState<AdminUserRow | null>(null);

  const { data, loading, error, refetch } = useAsyncData(
    () =>
      listAdminUsers({
        page: table.page,
        pageSize: table.pageSize,
        search: table.search,
      }),
    [table.page, table.pageSize, table.search]
  );

  const users = data?.rows ?? [];
  const total = data?.total ?? 0;

  if (loading && !data) {
    return (
      <div className="flex h-96 items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-96 flex-col items-center justify-center gap-4">
        <AlertTriangle className="h-10 w-10 text-amber-500" />
        <p className="text-sm text-zinc-600">{error}</p>
        <Button onClick={refetch} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" /> Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">User Management</h1>
          <p className="text-sm text-zinc-500 mt-1">{total} total users</p>
        </div>
        <div className="flex items-center gap-3">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline"><Download className="h-4 w-4 mr-2" /> Export</Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-44">
              <DropdownMenuItem onClick={() => exportToCSV(users, 'users', [
                { key: 'full_name', label: 'Name' }, { key: 'phone', label: 'Phone' },
                { key: 'country', label: 'Country' }, { key: 'is_admin', label: 'Admin' },
                { key: 'created_at', label: 'Joined' },
              ])}><Download className="mr-2 h-4 w-4" /> CSV</DropdownMenuItem>
              <DropdownMenuItem onClick={() => exportToTSV(users, 'users', [
                { key: 'full_name', label: 'Name' }, { key: 'phone', label: 'Phone' },
                { key: 'country', label: 'Country' }, { key: 'is_admin', label: 'Admin' },
                { key: 'created_at', label: 'Joined' },
              ])}><FileSpreadsheet className="mr-2 h-4 w-4" /> Excel</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Link to="/users/create">
            <Button className="bg-indigo-600 hover:bg-indigo-700 text-white">
              <Plus className="h-4 w-4 mr-2" /> New User
            </Button>
          </Link>
        </div>
      </div>

      <Card>
        <DataTableToolbar>
          <DataTableSearch
            placeholder="Search by name or phone..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Role</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {users.length === 0 ? (
              <DataTableEmptyRow
                colSpan={6}
                icon={<UsersIcon className="h-8 w-8" />}
                message="No users found"
              />
            ) : (
              users.map((u) => (
                <TableRow key={u.id}>
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <div className="h-9 w-9 rounded-full bg-indigo-100 flex items-center justify-center text-indigo-700 font-bold text-xs">
                        {u.full_name ? u.full_name.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase() : "?"}
                      </div>
                      <div>
                        <p className="font-medium text-zinc-900">{u.full_name || "(Unnamed)"}</p>
                        {u.is_mock && <span className="text-[10px] text-zinc-400">Mock</span>}
                      </div>
                    </div>
                  </TableCell>
                  <TableCell className="font-mono text-xs text-zinc-600">{u.phone}</TableCell>
                  <TableCell><Badge variant="outline">{u.country}</Badge></TableCell>
                  <TableCell>
                    {u.is_admin ? (
                      <Badge variant="default" className="bg-indigo-100 text-indigo-800">Admin</Badge>
                    ) : (
                      <Badge variant="outline">Member</Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-sm text-zinc-500">
                    {new Date(u.created_at).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon" aria-label={`Open actions for ${u.full_name || u.phone}`}><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-48">
                        <DropdownMenuLabel>Actions</DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem onClick={() => setSelectedUser(u)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>

        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={total}
          onPageChange={table.setPage}
        />
      </Card>
      {/* Detail Sheet */}
      <DetailSheet
        open={!!selectedUser}
        onClose={() => setSelectedUser(null)}
        title={selectedUser?.full_name || "User Details"}
        subtitle={selectedUser?.phone}
      >
        {selectedUser && (
          <>
            <DetailSection title="Profile">
              <DetailRow label="Full Name" value={selectedUser.full_name || "(Unnamed)"} />
              <DetailRow label="Phone" value={selectedUser.phone} mono />
              <DetailRow label="Country" value={selectedUser.country} />
              <DetailRow label="MoMo Number" value={selectedUser.momo_number} mono />
            </DetailSection>
            <DetailSection title="Account">
              <DetailRow label="Role" value={
                selectedUser.is_admin
                  ? <Badge variant="default" className="bg-indigo-100 text-indigo-800">Admin</Badge>
                  : <Badge variant="outline">Member</Badge>
              } />
              <DetailRow label="Mock Account" value={selectedUser.is_mock ? "Yes" : "No"} />
              <DetailRow label="User ID" value={selectedUser.id} mono />
              <DetailRow label="Joined" value={new Date(selectedUser.created_at).toLocaleString()} />
            </DetailSection>
          </>
        )}
      </DetailSheet>
    </div>
  );
}
