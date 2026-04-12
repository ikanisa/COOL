import { useState } from "react";
import { Link } from "react-router-dom";
import { Search, Filter, Plus, Users as UsersIcon, MoreHorizontal, Eye, Loader2, RefreshCw, AlertTriangle, Inbox } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/lib/supabase";
import { useAsyncData } from "@/lib/hooks";

interface MemberRow {
  id: string;
  group_id: string;
  user_id: string;
  display_name: string;
  is_admin: boolean;
  contribution_amount: number;
  joined_at: string;
  group_name: string;
  user_phone: string;
}

const PAGE_SIZE = 20;

export function MembersList() {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);

  const { data, loading, error, refetch } = useAsyncData(async () => {
    const { data: rows, error: queryError, count } = await supabase
      .from("group_members")
      .select(`
        id, group_id, user_id, display_name, is_admin, contribution_amount, joined_at,
        groups!group_members_group_id_fkey ( name ),
        users!group_members_user_id_fkey ( phone )
      `, { count: "exact" })
      .order("joined_at", { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (queryError) throw new Error(queryError.message);

    const mapped: MemberRow[] = (rows ?? []).map((r: Record<string, unknown>) => {
      const group = r.groups as Record<string, string> | null;
      const user = r.users as Record<string, string> | null;
      return {
        id: r.id as string,
        group_id: r.group_id as string,
        user_id: r.user_id as string,
        display_name: r.display_name as string,
        is_admin: r.is_admin as boolean,
        contribution_amount: r.contribution_amount as number,
        joined_at: r.joined_at as string,
        group_name: group?.name ?? "(Unknown)",
        user_phone: user?.phone ?? "",
      };
    });

    return { rows: mapped, total: count ?? 0 };
  }, [page]);

  const members = data?.rows ?? [];
  const total = data?.total ?? 0;
  const filtered = search.trim()
    ? members.filter((m) =>
        m.display_name.toLowerCase().includes(search.toLowerCase()) ||
        m.group_name.toLowerCase().includes(search.toLowerCase()) ||
        m.user_phone.includes(search)
      )
    : members;

  if (loading && !data) {
    return <div className="flex h-96 items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-indigo-600" /></div>;
  }
  if (error) {
    return <div className="flex h-96 flex-col items-center justify-center gap-4"><AlertTriangle className="h-10 w-10 text-amber-500" /><p className="text-sm text-zinc-600">{error}</p><Button onClick={refetch} variant="outline" size="sm"><RefreshCw className="h-4 w-4 mr-2" /> Retry</Button></div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Members</h1>
          <p className="text-sm text-zinc-500 mt-1">{total} group members across all savings groups.</p>
        </div>
        <Link to="/members/create">
          <Button className="bg-indigo-600 hover:bg-indigo-700 text-white"><Plus className="h-4 w-4 mr-2" /> Add Member</Button>
        </Link>
      </div>

      <Card>
        <div className="p-4 border-b border-zinc-100 flex items-center gap-3">
          <div className="relative w-full max-w-sm">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
            <Input className="pl-9" placeholder="Search by name, group, or phone..." value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
          <Button variant="outline" size="icon"><Filter className="h-4 w-4" /></Button>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Member</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Group</TableHead>
              <TableHead>Role</TableHead>
              <TableHead>Contribution</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><Inbox className="h-8 w-8" /><p className="text-sm">No members found</p></div></TableCell></TableRow>
            ) : filtered.map((m) => (
              <TableRow key={m.id}>
                <TableCell>
                  <div className="flex items-center gap-3">
                    <div className="h-8 w-8 rounded-full bg-indigo-100 flex items-center justify-center text-indigo-700 font-bold text-xs">
                      {m.display_name ? m.display_name[0].toUpperCase() : "?"}
                    </div>
                    <span className="font-medium text-zinc-900">{m.display_name || "(Unnamed)"}</span>
                  </div>
                </TableCell>
                <TableCell className="font-mono text-xs text-zinc-500">{m.user_phone}</TableCell>
                <TableCell><Badge variant="outline">{m.group_name}</Badge></TableCell>
                <TableCell>{m.is_admin ? <Badge variant="default" className="bg-indigo-100 text-indigo-800">Admin</Badge> : <Badge variant="outline">Member</Badge>}</TableCell>
                <TableCell className="font-medium text-zinc-900">{(m.contribution_amount ?? 0).toLocaleString()} RWF</TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(m.joined_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-44">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                      <DropdownMenuItem><UsersIcon className="mr-2 h-4 w-4" /> View Group</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        <div className="flex items-center justify-between p-4 border-t border-zinc-100">
          <p className="text-sm text-zinc-500">Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of {total}</p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Button>
            <Button variant="outline" size="sm" disabled={(page + 1) * PAGE_SIZE >= total} onClick={() => setPage(page + 1)}>Next</Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
