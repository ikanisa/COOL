import * as React from "react"
import { cn } from "@/lib/utils"

function Badge({ className, variant = "default", ...props }: React.HTMLAttributes<HTMLDivElement> & { variant?: "default" | "secondary" | "success" | "warning" | "danger" | "outline" }) {
  return (
    <div
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
        {
          "bg-zinc-100 text-zinc-900": variant === "default",
          "bg-indigo-50 text-indigo-700": variant === "secondary",
          "bg-emerald-100 text-emerald-800": variant === "success",
          "bg-amber-100 text-amber-800": variant === "warning",
          "bg-rose-100 text-rose-800": variant === "danger",
          "text-zinc-950 border border-zinc-200": variant === "outline",
        },
        className
      )}
      {...props}
    />
  )
}

export { Badge }
