# SDK Package Contract (Static Compile-Time Aggregation)

This document defines the **SDK package** format exchanged between the HRPAuth
main service and the WebUI SDK handler (`HA-WebUI-SDKHandler`). It replaces the
old runtime JS SDK model (`sdk_url` + `window['<service-name>-sdk']`) with a
compile-time aggregation model: SDKs are shipped as self-contained source
packages, aggregated into a generated frontend, and compiled by the SDK handler.

## Design Positioning

- HRPAuth is the **single trusted broker** for SDK packages. Satellite
  services upload SDK packages to HRPAuth; the SDK handler pulls them from
  HRPAuth only. The handler never reaches satellite services directly.
- HRPAuth **validates** every uploaded package (archive safety, manifest
  correctness, conflict policy) before accepting it.
- The SDK handler aggregates all accepted packages into a fresh frontend build
  and publishes the compiled static assets atomically.
- Satellite services are deployed by the same operator as the WebUI; all
  satellite services are absolutely trusted by HRPAuth, and all authentication
  is performed by HRPAuth (Level 2 / Ops).

## Data Flow

```
Satellite service                    HRPAuth (main)                   HA-WebUI-SDKHandler
--------------                       ----------------                 ---------------------
POST /services/sdk-packages  ──►     validate + store (fs + Redis)
                                     GET /services/sdk-packages   ◄──  poll (fingerprint)
                                     GET /services/sdk-packages/:name ◄─ download archive
                                                                        copy template
                                                                        extract + inject SDKs
                                                                        merge npm deps
                                                                        npm install + tsc + vite build
                                                                        publish artifacts atomically
```

## Package Format

A SDK package is a single compressed archive of exactly one of:

- `tar.gz` (gzip-compressed tar)
- `zip`

The archive MUST contain exactly one `manifest.json` at its root. All other
files are SDK source files (TS/TSX/JS/JSON/CSS/static assets).

### Layout

```text
example-service-sdk.tar.gz
  manifest.json
  src/
    index.ts
    pages/
      ExamplePage.tsx
    components/
      Widget.tsx
  styles/
    example.css
```

- Relative paths inside the archive are preserved on injection.
- Path traversal (`..`, absolute paths) is rejected by HRPAuth and again by the
  SDK handler.
- Symbolic links and hard links are rejected.
- Allowed source extensions: `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`,
  `.json`, `.css`, plus static assets referenced by the source
  (`.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.woff`, `.woff2`, `.ttf`).

### Size Limits

- Maximum uncompressed and compressed package size is enforced by HRPAuth
  (`sdk_packages.max_package_size`, default `20971520` = 20 MiB).
- Exceeding the limit returns `413 sdk_package_too_large`.

## manifest.json Schema

```json
{
  "schema_version": 1,
  "name": "example-service",
  "version": "1.0.0",
  "routes": [
    {
      "path": "/example",
      "module": "src/pages/ExamplePage",
      "title": "Example"
    }
  ],
  "menu": [
    {
      "label": "Example",
      "path": "/example"
    }
  ],
  "dashboard": [
    {
      "label": "Example",
      "path": "/example"
    }
  ],
  "dependencies": {
    "some-lib": "^1.0.0"
  },
  "run_scripts": false
}
```

### Field Reference

| Field | Type | Required | Description |
|---|---|---|---|
| `schema_version` | int | yes | Manifest schema version. Currently `1`. |
| `name` | string | yes | Unique service name. `[a-z0-9]([a-z0-9-]*[a-z0-9])?`, max 64 chars. Uniquely identifies the package on HRPAuth. |
| `version` | string | yes | Semantic version (`major.minor.patch`). |
| `routes` | array | yes | Non-empty list of route entries (see below). |
| `routes[].path` | string | yes | Route path, MUST start with `/`, MUST NOT end with `/` (except root `/`), MUST NOT contain `?`/`#`/`..` segments. Becomes a React Router path. |
| `routes[].module` | string | yes | Relative path to a TS/TSX module inside the package (extension optional). The module MUST have a **default export** React component (used with `React.lazy`). MUST be inside the package (no `..`, no absolute path). |
| `routes[].title` | string | no | Optional document title hint. |
| `menu` | object/array | no | When present, adds one or more navbar items. Can be a single object or an array of objects. |
| `menu[].label` | string | yes* | Navbar display label. |
| `menu[].path` | string | yes* | Target route path, MUST reference an entry in `routes`. |
| `dashboard` | object/array | no | When present, adds one or more sidebar items on the Dashboard page. Can be a single object or an array of objects. |
| `dashboard[].label` | string | yes* | Dashboard display label. |
| `dashboard[].path` | string | yes* | Target route path, MUST reference an entry in `routes`. |
| `dependencies` | object | no | npm dependencies to merge into the generated frontend `package.json`. Keys are package names, values are npm version ranges. |
| `run_scripts` | bool | no | Whether npm lifecycle scripts (`preinstall`/`postinstall`/…) of the merged dependency tree may execute during install. **Default `false`** (install runs with `--ignore-scripts`). The handler may additionally enforce a configured npm blacklist. |

> `menu.path` / `dashboard.path` reference **routes declared by the same
> service**. Cross-service references are not allowed.

### Conflict Policy

- A package is uniquely identified by `name`.
- Uploading a new package whose `name` already exists is **rejected**
  (`409 sdk_package_conflict`). Replace requires `DELETE` first.
- Dependency conflicts are **not** detected at upload time; they surface as a
  build failure in the SDK handler, which keeps the previous published version.

## Validation Rules (enforced by HRPAuth at upload)

1. Archive format must be `tar.gz` or `zip`.
2. Archive must contain exactly one root-level `manifest.json`.
3. `manifest.json` must parse and satisfy the schema above.
4. All file paths must be relative, inside the package, free of `..` and
   absolute segments; no symlinks/hard links.
5. `routes[].module` must resolve inside the package.
6. Package size must not exceed `max_package_size`.
7. Duplicate `name` → `409 sdk_package_conflict`.

## Generated Frontend Contract (HA-WebUI-SDKHandler)

The handler produces the following generated modules under
`src/generated/` in the build frontend:

| File | Exports | Consumer |
|---|---|---|
| `sdk-manifest.ts` | `sdkManifest: SdkManifestEntry[]` | diagnostics / metadata |
| `sdk-routes.tsx` | `sdkRoutes: RouteObject[]` (lazy components) | `App.tsx` route tree |
| `sdk-navbar.tsx` | `sdkNavbarItems: SdkNavbarItem[]` | `Navbar.tsx` |
| `sdk-dashboard.tsx` | `sdkDashboardItems: SdkDashboardItem[]` | `Dashboard.tsx` |

Type contracts are defined in `HRPAuth-Web/src/types/generated-sdk.ts`
(human-maintained, stable):

```ts
export interface SdkManifestEntry {
  name: string;
  version: string;
  routes: { path: string; module: string; title?: string }[];
  menu?: { label: string; path: string }[];
  dashboard?: { label: string; path: string }[];
  runScripts: boolean;
  sha256: string;
}

export interface SdkNavbarItem {
  key: string;      // service name
  label: string;
  path: string;
}

export interface SdkDashboardItem {
  key: string;      // service name
  label: string;
  element: React.ReactNode; // lazy component rendering route content
}
```

Every SDK service directory is injected under
`src/generated/services/<name>/` preserving the package's internal layout.

## Build Policy

- `frontend-original/` (template) is **read-only**; every build fully copies it
  to a fresh work directory.
- All SDK packages are re-injected on every build (no incremental leftovers).
- npm dependencies are merged from every manifest's `dependencies`.
- `npm install` runs with `--ignore-scripts` unless the package declares
  `run_scripts: true` (or the operator explicitly allows it).
- Build pipeline: `npm install` → `tsc -b` → `vite build`.
- On success, the new `dist` is published to a versioned artifact directory and
  the `current` pointer is switched atomically.
- On failure, the previous `current` artifact is kept serving traffic.

## Error Codes

New error codes introduced by this contract (registered in
`docs/api/error-codes.md`):

| Code | Meaning |
|---|---|
| `sdk_package_conflict` | A package with the same name already exists |
| `sdk_package_not_found` | Requested SDK package does not exist |
| `sdk_package_invalid` | Archive is malformed or unreadable |
| `sdk_package_invalid_manifest` | `manifest.json` is missing or fails validation |
| `sdk_package_invalid_path` | Archive contains illegal path (traversal/absolute/symlink) |
| `sdk_package_too_large` | Package exceeds the configured size limit |
