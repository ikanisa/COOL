import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Search, Filter, Plus, MoreHorizontal, Eye, Edit, Users as UsersIcon, Loader2, RefreshCw, AlertTriangle, FolderOpen } from "lucide-react";
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

interface SavingsGroup {
  id: string;
  name: string;
  description: string | null;
  target_amount: number;
  monthly_contribution: number | null;
  frequency: string;
  member_count: number;
  total_collected: number;
  invite_code: string;
  is_closed: boolean;
  is_active: boolean;
  created_at: string;
}

interface GroupsData {
  savings_momo_code: string;
  total_savings_groups: number;
  active_savings_groups: number;
  total_community_groups: number;
  total_members_in_savings: number;
  total_collected: number;
  savings_groups: SavingsGroup[];
  community_groups: Array<{ id: string; name: string; member_count: number; created_at: string }>;
}

export function GroupsList() {
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const [tab, setTab] = useState<"savings" | "community">("savings");

  const { data, loading, error, refetch } = useAsyncData(async () => {
    const { data, error } = await supabase.rpc("admin_get_savings_groups_detail");
    if (error) throw new Error(error.message);
    return data as GroupsData;
  });

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
    (g) => !search.trim() || g.name.toLowerCase().includes(search.toLowerCase())
  );
  const communityGroups = (data?.community_groups ?? []).filter(
    (g) => !search.trim() || g.name.toLowerCase().includes(search.toLowerCase())
  );

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
        <div className="p-4 border-b border-zinc-100 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <div className="relative w-full sm:w-80">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
              <Input placeholder="Search groups..." className="pl-9" value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
            <Button variant="outline" size="icon"><Filter className="h-4 w-4" /></Button>
          </div>
          <div className="flex items-center gap-2">
            <Badge
              variant={tab === "savings" ? "default" : "outline"}
              className={tab === "savings" ? "bg-indigo-600 text-white cursor-pointer" : "cursor-pointer"}
              onClick={() => setTab("savings")}
            >
              Savings ({data?.total_savings_groups ?? 0})
            </Badge>
            <Badge
              variant={tab === "community" ? "default" : "outline"}
              className={tab === "community" ? "bg-indigo-600 text-white cursor-pointer" : "cursor-pointer"}
              onClick={() => setTab("community")}
            >
              Community ({data?.total_community_groups ?? 0})
            </Badge>
          </div>
        </div>

        {data?.savings_momo_code && (
          <div className="px-4 py-2 bg-zinc-50/50 border-b border-zinc-100 text-xs font-medium text-zinc-500">
            MoMo Code: <span className="font-mono text-zinc-700">{data.savings_momo_code}</span> • Total collected: <span className="font-bold text-emerald-600">{(data.total_collected ?? 0).toLocaleString()} RWF</span>
          </div>
        )}

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              {tab === "savings" && <TableHead>Target</TableHead>}
              {tab === "savings" && <TableHead>Monthly</TableHead>}
              {tab === "savings" && <TableHead>Collected</TableHead>}
              <TableHead>Members</TableHead>
              {tab === "savings" && <TableHead>Invite Code</TableHead>}
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {tab === "savings" && savingsGroups.length === 0 && (
              <TableRow><TableCell colSpan={9} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><FolderOpen className="h-8 w-8" /><p className="text-sm">No savings groups found</p></div></TableCell></TableRow>
            )}
            {tab === "savings" && savingsGroups.map((g) => (
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
                    <DropdownMenuTrigger asChild><Button variant="ghost" size="icon"><MoreHorizontal className="h-4 w-4 text-zinc-400" /></Button></DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuLabel>Actions</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => navigate(`/groups/create?groupId=${g.id}`)}><Eye className="mr-2 h-4 w-4" /> View Details</DropdownMenuItem>
                      <DropdownMenuItem onClick={() => navigate(`/groups/create?groupId=${g.id}`)}><Edit className="mr-2 h-4 w-4" /> Edit Group</DropdownMenuItem>
                      <DropdownMenuItem onClick={() => navigate(`/members/create?groupId=${g.id}`)}><UsersIcon className="mr-2 h-4 w-4" /> Manage Members</DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
            {tab === "community" && communityGroups.length === 0 && (
              <TableRow><TableCell colSpan={5} className="h-32 text-center"><div className="flex flex-col items-center gap-2 text-zinc-400"><FolderOpen className="h-8 w-8" /><p className="text-sm">No community groups found</p></div></TableCell></TableRow>
            )}
            {tab === "community" && communityGroups.map((g) => (
              <TableRow key={g.id}>
                <TableCell className="font-medium text-zinc-900">{g.name}</TableCell>
                <TableCell><div className="flex items-center gap-1"><UsersIcon className="h-3.5 w-3.5 text-zinc-400" />{g.member_count}</div></TableCell>
                <TableCell><Badge variant="success">Active</Badge></TableCell>
                <TableCell className="text-sm text-zinc-500">{new Date(g.created_at).toLocaleDateString()}</TableCell>
                <TableCell className="text-right"><Button variant="ghost" size="icon" onClick={() => navigate(`/members/create?groupId=${g.id}`)}><Eye className="h-4 w-4 text-zinc-400" /></Button></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  );
}
