type SurfaceStatus = "active" | "retired-fail-closed" | "not-implemented";

interface WebSurface {
  id: string;
  path: string | null;
  status: SurfaceStatus;
  buildCommand: string | null;
  backendEnforced: boolean;
  releaseOwner: string | null;
}

function assert(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

const repoRoot = new URL("../../../", import.meta.url);
const registryPath = new URL(
  "docs/product/web-surface-registry.json",
  repoRoot,
);
const activationContractsPath = new URL(
  "docs/product/web-surface-activation-contracts.md",
  repoRoot,
);
const pwaReadmePath = new URL("apps/pwa/README.md", repoRoot);

async function loadRegistry(): Promise<WebSurface[]> {
  return JSON.parse(await Deno.readTextFile(registryPath)) as WebSurface[];
}

Deno.test({
  name: "web surface registry blocks fake active apps",
  permissions: { read: true },
  async fn() {
    const registry = await loadRegistry();
    const ids = new Set<string>();

    for (const surface of registry) {
      assert(!ids.has(surface.id), `duplicate web surface id: ${surface.id}`);
      ids.add(surface.id);

      if (surface.status === "active") {
        const surfacePath = surface.path;

        if (surfacePath === null) {
          throw new Error(`${surface.id} active surface needs a path`);
        }
        assert(
          surface.buildCommand !== null,
          `${surface.id} active surface needs a build/test command`,
        );
        assert(
          surface.releaseOwner !== null,
          `${surface.id} active surface needs a release owner`,
        );
        await Deno.stat(new URL(surfacePath, repoRoot));
        continue;
      }

      if (surface.status === "not-implemented") {
        assert(surface.path === null, `${surface.id} must not point at fake UI`);
        assert(
          surface.buildCommand === null,
          `${surface.id} must not publish a build command before implementation`,
        );
      }
    }
  },
});

Deno.test({
  name: "missing web surfaces have activation contracts",
  permissions: { read: true },
  async fn() {
    const registry = await loadRegistry();
    const contracts = await Deno.readTextFile(activationContractsPath);
    const requiredMissingIds = [
      "venue-dashboard",
      "agent-console",
      "promotions-approval",
      "pwa",
    ];

    for (const id of requiredMissingIds) {
      const surface = registry.find((entry) => entry.id === id);
      if (surface === undefined) {
        throw new Error(`${id} registry entry must exist`);
      }
      assert(surface.status !== "active", `${id} must not be active yet`);
    }

    for (const heading of [
      "Venue Manager Dashboard",
      "Agent Admin Console",
      "Promotions Approval Console",
      "User PWA",
    ]) {
      assert(
        contracts.includes(`## ${heading}`),
        `${heading} activation contract is missing`,
      );
    }
  },
});

Deno.test({
  name: "retired PWA remains fail-closed",
  permissions: { read: true },
  async fn() {
    const registry = await loadRegistry();
    const pwa = registry.find((surface) => surface.id === "pwa");
    const readme = await Deno.readTextFile(pwaReadmePath);

    if (pwa === undefined) {
      throw new Error("PWA registry entry must exist");
    }
    assert(pwa.status === "retired-fail-closed", "PWA must be marked retired");
    assert(pwa.path === "apps/pwa", "retired PWA path must stay explicit");
    assert(pwa.buildCommand === null, "retired PWA must not publish a build");
    assert(/fail closed|retired/i.test(readme), "PWA README must fail closed");
    assert(
      /Do not add production UI/i.test(readme),
      "PWA README must block accidental production UI",
    );
  },
});
