/**
 * Shared export utility for admin table pages.
 * Zero-dependency CSV + PDF-ready data formatting.
 */

/** Convert array of objects to CSV string and trigger download */
export function exportToCSV<T extends object>(
  data: T[],
  filename: string,
  columns?: { key: keyof T; label: string }[]
) {
  if (data.length === 0) return;

  const cols = columns ?? Object.keys(data[0]).map((k) => ({ key: k as keyof T, label: String(k) }));
  const header = cols.map((c) => `"${c.label}"`).join(",");
  const rows = data.map((row) =>
    cols.map((c) => {
      const val = row[c.key];
      if (val === null || val === undefined) return '""';
      const str = String(val).replace(/"/g, '""');
      return `"${str}"`;
    }).join(",")
  );

  const csv = [header, ...rows].join("\n");
  const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
  triggerDownload(blob, `${filename}.csv`);
}

/** Format data as tab-separated for quick Excel paste */
export function exportToTSV<T extends object>(
  data: T[],
  filename: string,
  columns?: { key: keyof T; label: string }[]
) {
  if (data.length === 0) return;

  const cols = columns ?? Object.keys(data[0]).map((k) => ({ key: k as keyof T, label: String(k) }));
  const header = cols.map((c) => c.label).join("\t");
  const rows = data.map((row) =>
    cols.map((c) => {
      const val = row[c.key];
      if (val === null || val === undefined) return "";
      return String(val).replace(/\t/g, " ").replace(/\n/g, " ");
    }).join("\t")
  );

  const tsv = [header, ...rows].join("\n");
  const blob = new Blob([tsv], { type: "text/tab-separated-values;charset=utf-8;" });
  triggerDownload(blob, `${filename}.xls`);
}

function triggerDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
