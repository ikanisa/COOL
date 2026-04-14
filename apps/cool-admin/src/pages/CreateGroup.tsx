import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, Save, Loader2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { supabase } from "@/lib/supabase";
import { toast } from "sonner";

export function CreateGroup() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState({
    name: "",
    description: "",
    targetAmount: "",
    monthlyContribution: "",
    frequency: "monthly",
  });

  const update = (field: string, value: string) => {
    setForm((prev) => ({ ...prev, [field]: value }));
    setError(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) {
      setError("Group name is required.");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const { data, error: rpcError } = await supabase.rpc("admin_create_savings_group", {
        p_name: form.name.trim(),
        p_description: form.description.trim() || null,
        p_target_amount: form.targetAmount ? parseInt(form.targetAmount) : 0,
        p_monthly_contribution: form.monthlyContribution ? parseInt(form.monthlyContribution) : null,
        p_frequency: form.frequency,
      });

      if (rpcError) throw new Error(rpcError.message);
      if (data?.status === "success") {
        toast.success(`Group "${form.name.trim()}" created successfully.`);
        navigate("/groups");
      } else {
        setError("Failed to create group.");
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to create group.";
      setError(msg);
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center gap-4">
        <Link to="/groups">
          <Button variant="outline" size="icon"><ArrowLeft className="h-4 w-4" /></Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Create Savings Group</h1>
          <p className="text-sm text-zinc-500 mt-1">Set up a new savings group with centralized MoMo collection.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Group Details</CardTitle>
            <CardDescription>Basic information about the savings group.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-900">Group Name *</label>
              <Input value={form.name} onChange={(e) => update("name", e.target.value)} placeholder="e.g. Kigali Savers Club" disabled={loading} />
            </div>
            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-900">Description</label>
              <Input value={form.description} onChange={(e) => update("description", e.target.value)} placeholder="Optional description..." disabled={loading} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">Target Amount (RWF)</label>
                <Input type="number" value={form.targetAmount} onChange={(e) => update("targetAmount", e.target.value)} placeholder="0" disabled={loading} />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">Monthly Contribution (RWF)</label>
                <Input type="number" value={form.monthlyContribution} onChange={(e) => update("monthlyContribution", e.target.value)} placeholder="0" disabled={loading} />
              </div>
            </div>
            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-900">Frequency</label>
              <select
                value={form.frequency}
                onChange={(e) => update("frequency", e.target.value)}
                disabled={loading}
                className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
              >
                <option value="daily">Daily</option>
                <option value="weekly">Weekly</option>
                <option value="monthly">Monthly</option>
              </select>
            </div>

            {error && <p className="text-sm text-rose-600 font-medium">{error}</p>}

            <div className="flex justify-end gap-3 pt-4">
              <Link to="/groups"><Button variant="outline" disabled={loading}>Cancel</Button></Link>
              <Button type="submit" disabled={loading} className="bg-indigo-600 hover:bg-indigo-700 text-white">
                {loading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Creating…</> : <><Save className="h-4 w-4 mr-2" /> Create Group</>}
              </Button>
            </div>
          </CardContent>
        </Card>
      </form>
    </div>
  );
}
