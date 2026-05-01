import { useState, useEffect, useCallback } from "react";
import { X, Loader2, Save } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  createAdminLoan,
  listLoanGroupOptions,
  listLoanMemberOptions,
  type LoanGroupOption,
  type LoanMemberOption,
} from "@/lib/api/admin-loans";
import { toast } from "sonner";

interface CreateLoanSheetProps {
  open: boolean;
  onClose: () => void;
  onCreated: () => void;
}

const LOAN_TYPES = [
  { value: "general", label: "General" },
  { value: "solar", label: "Solar" },
  { value: "insurance", label: "Insurance" },
  { value: "taxes", label: "Taxes" },
  { value: "emoto", label: "E-Moto" },
];

const FREQUENCIES = [
  { value: "daily", label: "Daily" },
  { value: "weekly", label: "Weekly" },
  { value: "monthly", label: "Monthly" },
];

export function CreateLoanSheet({ open, onClose, onCreated }: CreateLoanSheetProps) {
  const [saving, setSaving] = useState(false);
  const [groups, setGroups] = useState<LoanGroupOption[]>([]);
  const [members, setMembers] = useState<LoanMemberOption[]>([]);
  const [loadingMembers, setLoadingMembers] = useState(false);

  // Form state
  const [groupId, setGroupId] = useState("");
  const [memberId, setMemberId] = useState("");
  const [loanType, setLoanType] = useState("general");
  const [initialAmount, setInitialAmount] = useState("");
  const [repaymentAmount, setRepaymentAmount] = useState("");
  const [repaymentFrequency, setRepaymentFrequency] = useState("daily");
  const [dueDate, setDueDate] = useState("");
  const [notes, setNotes] = useState("");

  // Load groups on mount
  useEffect(() => {
    if (!open) return;
    (async () => {
      try {
        setGroups(await listLoanGroupOptions());
      } catch (error) {
        toast.error(
          error instanceof Error ? error.message : "Failed to load groups."
        );
      }
    })();
  }, [open]);

  // Load members when group changes
  const loadMembers = useCallback(async (gid: string) => {
    if (!gid) { setMembers([]); return; }
    setLoadingMembers(true);
    try {
      setMembers(await listLoanMemberOptions(gid));
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Failed to load members."
      );
      setMembers([]);
    } finally {
      setLoadingMembers(false);
    }
  }, []);

  useEffect(() => {
    setMemberId("");
    loadMembers(groupId);
  }, [groupId, loadMembers]);

  // Reset form when sheet opens
  useEffect(() => {
    if (open) {
      setGroupId("");
      setMemberId("");
      setLoanType("general");
      setInitialAmount("");
      setRepaymentAmount("");
      setRepaymentFrequency("daily");
      setDueDate("");
      setNotes("");
    }
  }, [open]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!groupId || !memberId || !initialAmount || !repaymentAmount) {
      toast.error("Please fill all required fields.");
      return;
    }

    const amount = parseFloat(initialAmount);
    const repayment = parseFloat(repaymentAmount);

    if (isNaN(amount) || amount <= 0) {
      toast.error("Initial amount must be a positive number.");
      return;
    }
    if (isNaN(repayment) || repayment <= 0) {
      toast.error("Repayment amount must be a positive number.");
      return;
    }

    setSaving(true);
    try {
      // Find actual user_id from selected member
      const selectedMember = members.find((m) => m.user_id === memberId);
      if (!selectedMember) {
        toast.error("Invalid member selected.");
        setSaving(false);
        return;
      }

      await createAdminLoan({
        memberId: selectedMember.user_id,
        groupId,
        loanType,
        initialAmount: amount,
        repaymentAmount: repayment,
        repaymentFrequency,
        dueDate,
        notes,
      });

      toast.success("Loan created successfully.");
      onCreated();
      onClose();
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Failed to create loan.";
      toast.error(message);
    } finally {
      setSaving(false);
    }
  };

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-[80] bg-black/30 backdrop-blur-sm transition-opacity"
        onClick={onClose}
      />
      {/* Sheet */}
      <div className="fixed inset-y-0 right-0 z-[85] w-full max-w-lg bg-white shadow-2xl border-l border-zinc-200 overflow-y-auto animate-in slide-in-from-right duration-300">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-zinc-100 sticky top-0 bg-white z-10">
          <div>
            <h2 className="text-lg font-bold text-zinc-900">Create New Loan</h2>
            <p className="text-sm text-zinc-500 mt-0.5">Issue a new loan to a group member</p>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg text-zinc-400 hover:bg-zinc-100 hover:text-zinc-600 transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          {/* Group */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-zinc-700">
              Group <span className="text-rose-500">*</span>
            </label>
            <select
              value={groupId}
              onChange={(e) => setGroupId(e.target.value)}
              required
              className="w-full h-10 rounded-lg border border-zinc-200 bg-zinc-50 px-3 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
            >
              <option value="">Select a group…</option>
              {groups.map((g) => (
                <option key={g.id} value={g.id}>{g.name}</option>
              ))}
            </select>
          </div>

          {/* Member */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-zinc-700">
              Member <span className="text-rose-500">*</span>
            </label>
            <select
              value={memberId}
              onChange={(e) => setMemberId(e.target.value)}
              required
              disabled={!groupId || loadingMembers}
              className="w-full h-10 rounded-lg border border-zinc-200 bg-zinc-50 px-3 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent disabled:opacity-50"
            >
              <option value="">
                {loadingMembers ? "Loading members…" : !groupId ? "Select a group first" : "Select a member…"}
              </option>
              {members.map((m) => (
                <option key={m.user_id} value={m.user_id}>
                  {m.display_name || "(Unnamed)"} — {m.user_phone}
                </option>
              ))}
            </select>
          </div>

          {/* Loan Type */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-zinc-700">Loan Type</label>
            <select
              value={loanType}
              onChange={(e) => setLoanType(e.target.value)}
              className="w-full h-10 rounded-lg border border-zinc-200 bg-zinc-50 px-3 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
            >
              {LOAN_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>

          {/* Amount Row */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-700">
                Initial Amount (RWF) <span className="text-rose-500">*</span>
              </label>
              <Input
                type="number"
                min="1"
                step="any"
                placeholder="e.g. 500,000"
                value={initialAmount}
                onChange={(e) => setInitialAmount(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <label className="text-sm font-medium text-zinc-700">
                Repayment Amount (RWF) <span className="text-rose-500">*</span>
              </label>
              <Input
                type="number"
                min="1"
                step="any"
                placeholder="e.g. 5,000"
                value={repaymentAmount}
                onChange={(e) => setRepaymentAmount(e.target.value)}
                required
              />
            </div>
          </div>

          {/* Frequency */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-zinc-700">Repayment Frequency</label>
            <div className="flex gap-2">
              {FREQUENCIES.map((f) => (
                <button
                  key={f.value}
                  type="button"
                  onClick={() => setRepaymentFrequency(f.value)}
                  className={`flex-1 h-10 rounded-lg border text-sm font-medium transition-all ${
                    repaymentFrequency === f.value
                      ? "bg-indigo-50 border-indigo-300 text-indigo-700"
                      : "border-zinc-200 text-zinc-600 hover:bg-zinc-50"
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>

          {/* Due Date */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-zinc-700">Due Date (optional)</label>
            <Input
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
            />
          </div>

          {/* Notes */}
          <div className="space-y-2">
            <label className="text-sm font-medium text-zinc-700">Notes (optional)</label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Any additional notes about this loan…"
              rows={3}
              className="w-full rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm text-zinc-900 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent resize-none"
            />
          </div>

          {/* Summary */}
          {initialAmount && repaymentAmount && (
            <div className="rounded-xl bg-zinc-50 border border-zinc-200 p-4 space-y-2">
              <p className="text-xs font-semibold text-zinc-500 uppercase tracking-wider">Loan Summary</p>
              <div className="flex justify-between text-sm">
                <span className="text-zinc-600">Principal</span>
                <span className="font-semibold text-zinc-900">{Number(initialAmount).toLocaleString()} RWF</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-zinc-600">Repayment</span>
                <span className="font-semibold text-zinc-900">
                  {Number(repaymentAmount).toLocaleString()} RWF / {FREQUENCIES.find(f => f.value === repaymentFrequency)?.label}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-zinc-600">Est. Installments</span>
                <span className="font-semibold text-indigo-600">
                  {Math.ceil(Number(initialAmount) / Number(repaymentAmount))}
                </span>
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-3 pt-2">
            <Button
              type="button"
              variant="outline"
              className="flex-1"
              onClick={onClose}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              className="flex-1 bg-indigo-600 hover:bg-indigo-700 text-white"
              disabled={saving}
            >
              {saving ? (
                <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Creating…</>
              ) : (
                <><Save className="h-4 w-4 mr-2" /> Create Loan</>
              )}
            </Button>
          </div>
        </form>
      </div>
    </>
  );
}
