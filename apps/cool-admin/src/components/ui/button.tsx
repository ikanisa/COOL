import * as React from "react"
import { cn } from "@/lib/utils"

const Button = React.forwardRef<HTMLButtonElement, React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "default" | "outline" | "ghost" | "danger", size?: "default" | "sm" | "lg" | "icon", asChild?: boolean }>(
  ({ className, variant = "default", size = "default", asChild, children, ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(
          "inline-flex items-center justify-center whitespace-nowrap rounded-lg text-sm font-medium ring-offset-white transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
          {
            "bg-indigo-600 text-white hover:bg-indigo-700": variant === "default",
            "border border-zinc-200 bg-white hover:bg-zinc-100 hover:text-zinc-900": variant === "outline",
            "hover:bg-zinc-100 hover:text-zinc-900": variant === "ghost",
            "bg-rose-500 text-white hover:bg-rose-600": variant === "danger",
            "h-10 px-4 py-2": size === "default",
            "h-9 rounded-md px-3": size === "sm",
            "h-11 rounded-md px-8": size === "lg",
            "h-10 w-10": size === "icon",
          },
          className
        )}
        {...props}
      >
        {children}
      </button>
    )
  }
)
Button.displayName = "Button"

export { Button }
