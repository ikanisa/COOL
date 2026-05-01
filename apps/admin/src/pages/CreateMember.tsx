import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, Save, Loader2, Search } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useAsyncData } from "@/lib/hooks";
import {
  addAdminGroupMember,
  listSavingsGroupOptions,
  searchAdminUsers,
} from "@/lib/api/admin-members";
import { toast } from "sonner";

export function CreateMember() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [userSearch, setUserSearch] = useState("");
  const [selectedGroup, setSelectedGroup] = useState("");
  const [selectedUser, setSelectedUser] = useState<{ id: string; name: string; phone: string } | null>(null);
  const [displayName, setDisplayName] = useState("");

  const { data: groups } = useAsyncData(listSavingsGroupOptions);

  const { data: searchResults } = useAsyncData(
    () => searchAdminUsers(userSearch),
    [userSearch]
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedGroup || !selectedUser) {
      setError("Select both a group and a user.");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await addAdminGroupMember({
        groupId: selectedGroup,
        userId: selectedUser.id,
        displayName,
      });
      toast.success("Member added successfully.");
      navigate("/members");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to add member.";
      setError(msg);
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center gap-4">
        <Link to="/members"><Button variant="outline" size="icon"><ArrowLeft className="h-4 w-4" /></Button></Link>
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Add Group Member</h1>
          <p className="text-sm text-zinc-500 mt-1">Add an existing user to a savings group.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader><CardTitle>Member Details</CardTitle><CardDescription>Select a group and search for the user to add.</CardDescription></CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-900">Savings Group *</label>
              <select value={selectedGroup} onChange={(e) => setSelectedGroup(e.target.value)} disabled={loading} className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                <option value="">Select a group...</option>
                {(groups ?? []).map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              </select>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-900">Search User *</label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
                <Input className="pl-9" placeholder="Search by name or phone (min 3 chars)..." value={userSearch} onChange={(e) => { setUserSearch(e.target.value); setSelectedUser(null); }} disabled={loading} />
              </div>
              {(searchResults ?? []).length > 0 && !selectedUser && (
                <div className="border border-zinc-200 rounded-lg divide-y divide-zinc-100 max-h-48 overflow-y-auto">
                  {(searchResults ?? []).map((u) => (
                    <button key={u.id} type="button" onClick={() => { setSelectedUser({ id: u.id, name: u.full_name, phone: u.phone }); setDisplayName(u.full_name); setUserSearch(u.full_name); }} className="w-full flex items-center justify-between p-3 hover:bg-zinc-50 text-left">
                      <span className="text-sm font-medium text-zinc-900">{u.full_name || "(Unnamed)"}</span>
                      <span className="font-mono text-xs text-zinc-500">{u.phone}</span>
                    </button>
                  ))}
                </div>
              )}
              {selectedUser && (
                <div className="p-3 bg-emerald-50 rounded-lg text-sm text-emerald-700 font-medium">
                  ✓ Selected: {selectedUser.name} ({selectedUser.phone})
                </div>
              )}
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-900">Display Name (optional)</label>
              <Input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="Override display name..." disabled={loading} />
            </div>

            {error && <p className="text-sm text-rose-600 font-medium">{error}</p>}

            <div className="flex justify-end gap-3 pt-4">
              <Link to="/members"><Button variant="outline" disabled={loading}>Cancel</Button></Link>
              <Button type="submit" disabled={loading || !selectedGroup || !selectedUser} className="bg-indigo-600 hover:bg-indigo-700 text-white">
                {loading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Adding…</> : <><Save className="h-4 w-4 mr-2" /> Add Member</>}
              </Button>
            </div>
          </CardContent>
        </Card>
      </form>
    </div>
  );
}
