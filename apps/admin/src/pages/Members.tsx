import { useState } from "react";
import { Link } from "react-router-dom";
import { Plus, MoreHorizontal, Eye, Loader2, RefreshCw, AlertTriangle, Inbox } from "lucide-react";
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
import {
  listAdminMembers,
  type MemberRow,
} from "@/lib/api/admin-members";

const PAGE_SIZE = 20;

export function MembersList() {
  const table = useDataTableController({ pageSize: PAGE_SIZE });
  const [selectedMember, setSelectedMember] = useState<MemberRow | null>(null);

  const { data, loading, error, refetch } = useAsyncData(
    () =>
      listAdminMembers({
        page: table.page,
        pageSize: table.pageSize,
        search: table.search,
      }),
    [table.page, table.pageSize, table.search]
  );

  const members = data?.rows ?? [];
  const total = data?.total ?? 0;

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
        <DataTableToolbar>
          <DataTableSearch
            placeholder="Search by name, group, or phone..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>

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
            {members.length === 0 ? (
              <DataTableEmptyRow
                colSpan={7}
                icon={<Inbox className="h-8 w-8" />}
                message="No members found"
              />
            ) : members.map((m) => (
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
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" aria-label={`Open actions for ${m.display_name || m.user_phone}`}><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-44">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => setSelectedMember(m)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
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
        open={!!selectedMember}
        onClose={() => setSelectedMember(null)}
        title={selectedMember?.display_name || "Member Details"}
        subtitle={selectedMember?.user_phone}
      >
        {selectedMember && (
          <>
            <DetailSection title="Profile">
              <DetailRow label="Name" value={selectedMember.display_name || "(Unnamed)"} />
              <DetailRow label="Phone" value={selectedMember.user_phone} mono />
              <DetailRow label="Role" value={
                selectedMember.is_admin
                  ? <Badge variant="default" className="bg-indigo-100 text-indigo-800">Group Admin</Badge>
                  : <Badge variant="outline">Member</Badge>
              } />
            </DetailSection>
            <DetailSection title="Group & Contribution">
              <DetailRow label="Group" value={selectedMember.group_name} />
              <DetailRow label="Contribution" value={`${(selectedMember.contribution_amount ?? 0).toLocaleString()} RWF`} />
              <DetailRow label="Joined" value={new Date(selectedMember.joined_at).toLocaleString()} />
              <DetailRow label="Member ID" value={selectedMember.id} mono />
              <DetailRow label="User ID" value={selectedMember.user_id} mono />
            </DetailSection>
          </>
        )}
      </DetailSheet>
    </div>
  );
}
