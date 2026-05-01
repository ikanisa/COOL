import { useState } from "react";
import { Link } from "react-router-dom";
import { Plus, MoreHorizontal, Eye, Users as UsersIcon, Loader2, RefreshCw, AlertTriangle, FolderOpen } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  DataTableEmptyRow,
  DataTableFilterChips,
  DataTablePagination,
  DataTableSearch,
  DataTableToolbar,
  type DataTableFilterOption,
} from "@/components/ui/data-table-controls";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DetailSheet, DetailSection, DetailRow } from "@/components/ui/detail-sheet";
import { useDataTableController } from "@/lib/data-table-controller";
import { useAsyncData } from "@/lib/hooks";
import {
  getAdminGroupsDetail,
  type GroupsData,
  type SavingsGroup,
} from "@/lib/api/admin-groups";

const PAGE_SIZE = 20;
const GROUP_TYPE_FILTERS: Array<DataTableFilterOption<"savings" | "community">> = [
  { value: "savings", label: "Savings" },
  { value: "community", label: "Community" },
];

export function GroupsList() {
  const table = useDataTableController<"savings" | "community">({
    pageSize: PAGE_SIZE,
    initialFilter: "savings",
  });
  const [selectedGroup, setSelectedGroup] = useState<SavingsGroup | null>(null);
  const [selectedCommunityGroup, setSelectedCommunityGroup] =
    useState<GroupsData["community_groups"][number] | null>(null);

  const { data, loading, error, refetch } = useAsyncData(
    getAdminGroupsDetail,
    [],
    { refreshIntervalMs: 15000 }
  );

  if (loading) {
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

  const savingsGroups = (data?.savings_groups ?? []).filter(
    (g) =>
      !table.search.trim() ||
      g.name.toLowerCase().includes(table.search.toLowerCase())
  );
  const communityGroups = (data?.community_groups ?? []).filter(
    (g) =>
      !table.search.trim() ||
      g.name.toLowerCase().includes(table.search.toLowerCase())
  );
  const isSavingsTab = table.filter === "savings";
  const visibleSavingsGroups = table.paginate(savingsGroups);
  const visibleCommunityGroups = table.paginate(communityGroups);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Groups Management</h1>
          <p className="text-sm text-zinc-500 mt-1">
            {data?.total_savings_groups ?? 0} savings • {data?.total_community_groups ?? 0} community • {data?.total_members_in_savings ?? 0} members
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Link to="/groups/create">
            <Button className="bg-indigo-600 hover:bg-indigo-700 text-white">
              <Plus className="h-4 w-4 mr-2" /> New Group
            </Button>
          </Link>
        </div>
      </div>

      <Card>
        <DataTableToolbar
          trailing={
            <DataTableFilterChips
              value={table.filter}
              options={GROUP_TYPE_FILTERS.map((option) => ({
                ...option,
                count:
                  option.value === "savings"
                    ? data?.total_savings_groups ?? 0
                    : data?.total_community_groups ?? 0,
              }))}
              onChange={table.setFilter}
            />
          }
        >
          <DataTableSearch
            placeholder="Search groups..."
            value={table.search}
            onChange={table.setSearch}
          />
        </DataTableToolbar>

        {data?.savings_momo_code && (
          <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500">
            MoMo Code: <span className="font-mono text-zinc-700">{data.savings_momo_code}</span> • Total collected: <span className="font-bold text-emerald-600">{(data.total_collected ?? 0).toLocaleString()} RWF</span>
          </div>
        )}

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              {isSavingsTab && <TableHead>Target</TableHead>}
              {isSavingsTab && <TableHead>Monthly</TableHead>}
              {isSavingsTab && <TableHead>Collected</TableHead>}
              <TableHead>Members</TableHead>
              {isSavingsTab && <TableHead>Invite Code</TableHead>}
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isSavingsTab && savingsGroups.length === 0 && (
              <DataTableEmptyRow
                colSpan={9}
                icon={<FolderOpen className="h-8 w-8" />}
                message="No savings groups found"
              />
            )}
            {isSavingsTab && visibleSavingsGroups.map((g) => (
              <TableRow key={g.id}>
                <TableCell><div><p className="font-medium text-zinc-900">{g.name}</p>{g.description && <p className="text-xs text-zinc-500 truncate max-w-[200px]">{g.description}</p>}</div></TableCell>
                <TableCell className="font-medium text-zinc-900">{(g.target_amount ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-zinc-600">{(g.monthly_contribution ?? 0).toLocaleString()}</TableCell>
                <TableCell className="font-bold text-emerald-600">{(g.total_collected ?? 0).toLocaleString()}</TableCell>
                <TableCell><div className="flex items-center gap-1"><UsersIcon className="h-3.5 w-3.5 text-zinc-400" />{g.member_count}</div></TableCell>
                <TableCell className="font-mono text-xs text-zinc-500">{g.invite_code}</TableCell>
                <TableCell><Badge variant={g.is_closed ? "danger" : g.is_active ? "success" : "warning"}>{g.is_closed ? "Closed" : g.is_active ? "Active" : "Inactive"}</Badge></TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(g.created_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" aria-label={`Open actions for ${g.name}`}><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => setSelectedGroup(g)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
            {!isSavingsTab && communityGroups.length === 0 && (
              <DataTableEmptyRow
                colSpan={5}
                icon={<FolderOpen className="h-8 w-8" />}
                message="No community groups found"
              />
            )}
            {!isSavingsTab && visibleCommunityGroups.map((g) => (
              <TableRow key={g.id}>
                <TableCell className="font-medium text-zinc-900">{g.name}</TableCell>
                <TableCell><div className="flex items-center gap-1"><UsersIcon className="h-3.5 w-3.5 text-zinc-400" />{g.member_count}</div></TableCell>
                <TableCell><Badge variant="success">Active</Badge></TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(g.created_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right">
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`View details for ${g.name}`}
                    onClick={() => setSelectedCommunityGroup(g)}
                  >
                    <Eye className="h-4 w-4 text-zinc-400" />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <DataTablePagination
          page={table.page}
          pageSize={table.pageSize}
          total={isSavingsTab ? savingsGroups.length : communityGroups.length}
          onPageChange={table.setPage}
        />
      </Card>
      {/* Detail Sheet */}
      <DetailSheet
        open={!!selectedGroup}
        onClose={() => setSelectedGroup(null)}
        title={selectedGroup?.name || "Group Details"}
        subtitle={selectedGroup?.description || undefined}
      >
        {selectedGroup && (
          <>
            <DetailSection title="Savings">
              <DetailRow label="Target Amount" value={`${(selectedGroup.target_amount ?? 0).toLocaleString()} RWF`} />
              <DetailRow label="Monthly Contribution" value={`${(selectedGroup.monthly_contribution ?? 0).toLocaleString()} RWF`} />
              <DetailRow label="Total Collected" value={`${(selectedGroup.total_collected ?? 0).toLocaleString()} RWF`} />
              <DetailRow label="Frequency" value={selectedGroup.frequency} />
            </DetailSection>
            <DetailSection title="Members & Status">
              <DetailRow label="Member Count" value={selectedGroup.member_count} />
              <DetailRow label="Invite Code" value={selectedGroup.invite_code} mono />
              <DetailRow label="Status" value={
                <Badge variant={selectedGroup.is_closed ? "danger" : selectedGroup.is_active ? "success" : "warning"}>
                  {selectedGroup.is_closed ? "Closed" : selectedGroup.is_active ? "Active" : "Inactive"}
                </Badge>
              } />
              <DetailRow label="Group ID" value={selectedGroup.id} mono />
              <DetailRow label="Created" value={new Date(selectedGroup.created_at).toLocaleString()} />
            </DetailSection>
          </>
        )}
      </DetailSheet>
      <DetailSheet
        open={!!selectedCommunityGroup}
        onClose={() => setSelectedCommunityGroup(null)}
        title={selectedCommunityGroup?.name || "Community Group Details"}
      >
        {selectedCommunityGroup && (
          <DetailSection title="Group">
            <DetailRow label="Member Count" value={selectedCommunityGroup.member_count} />
            <DetailRow label="Group ID" value={selectedCommunityGroup.id} mono />
            <DetailRow label="Created" value={new Date(selectedCommunityGroup.created_at).toLocaleString()} />
          </DetailSection>
        )}
      </DetailSheet>
    </div>
  );
}
