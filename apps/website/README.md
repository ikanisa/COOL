# Website

Static Vite website for public landing, privacy, terms, and account-deletion
surfaces.

## Commands

- `npm --prefix apps/website run dev`
- `npm --prefix apps/website run build`
- `npm --prefix apps/website run preview`

## Boundaries

- Keep marketing/legal content here unless it becomes app runtime behavior.
- Shared brand assets and design tokens should move into `packages/design-system`
  only after a production app consumes the same contract.
- Do not add backend secrets or service-role logic to this app.
