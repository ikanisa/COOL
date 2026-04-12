import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, Save, Loader2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { supabase } from "@/lib/supabase";

export function CreateUser() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState({
    fullName: "",
    phone: "",
    country: "RW",
    isAdmin: false,
  });

  const update = (field: string, value: string | boolean) => {
    setForm((prev) => ({ ...prev, [field]: value }));
    setError(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.fullName.trim() || !form.phone.trim()) {
      setError("Name and phone are required.");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const phone = form.phone.startsWith("+") ? form.phone : `+250${form.phone.replace(/\s/g, "")}`;

      // Create user in the public.users table
      const { error: insertError } = await supabase.from("users").insert({
        phone,
        full_name: form.fullName.trim(),
        country: form.country,
        is_admin: form.isAdmin,
        is_mock: false,
      });

      if (insertError) throw new Error(insertError.message);

      navigate("/users");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create user.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center gap-4">
        <Link to="/users"><Button variant="outline" size="icon"><ArrowLeft className="h-4 w-4" /></Button></Link>
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-zinc-900">Create User</h1>
          <p className="text-sm text-zinc-500 mt-1">Register a new user on the platform.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader><CardTitle>User Information</CardTitle><CardDescription>Basic profile details for the new user.</CardDescription></CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="col-span-2 space-y-2">
                <label className="text-sm font-medium text-zinc-900">Full Name *</label>
                <Input value={form.fullName} onChange={(e) => update("fullName", e.target.value)} placeholder="Jean Claude Doe" disabled={loading} />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">Phone Number *</label>
                <Input type="tel" value={form.phone} onChange={(e) => update("phone", e.target.value)} placeholder="+250 788 123 456" disabled={loading} />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-zinc-900">Country</label>
                <select value={form.country} onChange={(e) => update("country", e.target.value)} disabled={loading} className="w-full h-10 px-3 rounded-lg border border-zinc-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500">
                  <option value="RW">Rwanda</option>
                  <option value="MT">Malta</option>
                </select>
              </div>
            </div>

            <div className="flex items-center gap-3 pt-2">
              <input type="checkbox" id="isAdmin" checked={form.isAdmin} onChange={(e) => update("isAdmin", e.target.checked)} disabled={loading} className="h-4 w-4 rounded border-zinc-300 text-indigo-600" />
              <label htmlFor="isAdmin" className="text-sm font-medium text-zinc-700">Grant admin privileges</label>
            </div>

            {error && <p className="text-sm text-rose-600 font-medium">{error}</p>}

            <div className="flex justify-end gap-3 pt-4">
              <Link to="/users"><Button variant="outline" disabled={loading}>Cancel</Button></Link>
              <Button type="submit" disabled={loading} className="bg-indigo-600 hover:bg-indigo-700 text-white">
                {loading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Creating…</> : <><Save className="h-4 w-4 mr-2" /> Create User</>}
              </Button>
            </div>
          </CardContent>
        </Card>
      </form>
    </div>
  );
}
