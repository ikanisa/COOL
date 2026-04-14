import { useState, useCallback, useRef } from "react";
import { Link } from "react-router-dom";
import { Search, Filter, Plus, MoreHorizontal, Eye, ShieldCheck, UserCog, Loader2, RefreshCw, AlertTriangle, Users as UsersIcon, Download, FileSpreadsheet } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DetailSheet, DetailSection, DetailRow } from "@/components/ui/detail-sheet";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";
import { exportToCSV, exportToTSV } from "@/lib/export";
import { toast } from "sonner";

interface UserRow {
  id: string;
  phone: string;
  full_name: string;
  country: string;
  is_admin: boolean;
  is_mock: boolean;
  created_at: string;
  momo_number: string | null;
}

const PAGE_SIZE = 20;

export function UsersList() {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const [selectedUser, setSelectedUser] = useState<UserRow | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const handleSearch = useCallback((value: string) => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setSearch(value);
      setPage(0);
    }, 300);
  }, []);

  const { data, loading, error, refetch } = useAsyncData(async () => {
    let query = supabase
      .from("users")
      .select("id, phone, full_name, country, is_admin, is_mock, created_at, momo_number", { count: "exact" })
      .order("created_at", { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (search.trim()) {
      query = query.or(`full_name.ilike.%${search.trim()}%,phone.ilike.%${search.trim()}%`);
    }

    const { data: rows, error: queryError, count } = await query;
    if (queryError) throw new Error(queryError.message);
    return { rows: (rows ?? []) as UserRow[], total: count ?? 0 };
  }, [page, search]);

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
        <div className="p-4 border-b border-zinc-100 flex flex-col sm:flex-row sm:items-center gap-4">
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input
                placeholder="Search by name or phone..."
                className="pl-9"
                defaultValue={search}
                onChange={(e) => handleSearch(e.target.value)}
              />
            </div>
            <Button variant="outline" size="icon" onClick={() => toast.info("Advanced filters coming soon.")}>
              <Filter className="h-4 w-4 text-zinc-500" />
            </Button>
          </div>
        </div>

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
              <TableRow>
                <TableCell colSpan={6} className="h-32 text-center">
                  <div className="flex flex-col items-center gap-2 text-zinc-400">
                    <UsersIcon className="h-8 w-8" />
                    <p className="text-sm">No users found</p>
                  </div>
                </TableCell>
              </TableRow>
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
                        <Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-48">
                        <DropdownMenuLabel>Actions</DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem onClick={() => setSelectedUser(u)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                        <DropdownMenuItem onClick={() => toast.info("Edit User coming soon.")}><UserCog className="mr-2 h-4 w-4" /> Edit User</DropdownMenuItem>
                        <DropdownMenuItem onClick={() => toast.info("Manage Roles coming soon.")}><ShieldCheck className="mr-2 h-4 w-4" /> Manage Roles</DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>

        {/* Pagination */}
        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">
            Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of {total}
          </p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage(page - 1)}>
              Previous
            </Button>
            <Button variant="outline" size="sm" disabled={(page + 1) * PAGE_SIZE >= total} onClick={() => setPage(page + 1)}>
              Next
            </Button>
          </div>
        </div>
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
