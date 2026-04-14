import { Link } from "react-router-dom";
import { Home, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";

export function NotFound() {
  return (
    <div className="flex flex-col items-center justify-center py-24 gap-6 text-center">
      <div className="h-20 w-20 rounded-2xl bg-indigo-50 flex items-center justify-center">
        <span className="text-4xl font-display font-bold text-indigo-600">404</span>
      </div>
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-zinc-900 mb-2">
          Page not found
        </h1>
        <p className="text-sm text-zinc-500 max-w-md">
          The page you're looking for doesn't exist or has been moved.
          Check the URL or navigate back to the dashboard.
        </p>
      </div>
      <div className="flex items-center gap-3">
        <Button variant="outline" onClick={() => window.history.back()}>
          <ArrowLeft className="h-4 w-4 mr-2" />
          Go Back
        </Button>
        <Link to="/">
          <Button>
            <Home className="h-4 w-4 mr-2" />
            Dashboard
          </Button>
        </Link>
      </div>
    </div>
  );
}
