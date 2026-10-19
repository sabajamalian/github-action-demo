# OctoCAT Supply coding standards

These are the organization's coding standards for this repository. Reviewers use them, and the
[Copilot coding standards review](workflows/copilot-coding-standards.yml) workflow checks pull
requests against them.

## How the review applies these standards

- Only code that the pull request adds or changes is in scope. Existing code that the PR doesn't
  touch isn't reviewed, even when it doesn't follow a standard.
- A standard is **N/A** when the PR doesn't touch the area it covers, for example the React
  standards on a PR that only changes the API.
- Each standard gets one result: **Met**, **Not met**, or **N/A**. A PR passes when no standard is
  Not met.
- The IDs (CS-01 to CS-08) are stable. Refer to them in reviews, don't renumber them, and add new
  standards at the end with the next free ID.

## Standards

### CS-01: No `any` in TypeScript

**Rule:** New or changed TypeScript, including tests, doesn't use `any` (annotations, `as any`
casts, `any[]`, or `Array<any>`).

**Why:** `any` turns off type checking, so mistakes the compiler would catch show up at runtime
instead.

**Compliant:** Use the model interfaces in `api/src/models` (`Branch`, `Product`, and so on), a
local interface or type, a generic, or `unknown` that's narrowed before use.

### CS-02: No leftover debug logging

**Rule:** New or changed code doesn't add `console.log`, `console.debug`, or `debugger` statements.

**Why:** Debug output clutters the API and browser logs and can leak request data.

**Compliant:** Remove debug statements before opening the PR. `console.error` or `console.warn` in
a real error path is fine, as in the `catch` block of `ProductForm.tsx`. The one-time startup
messages in `api/src/index.ts` are the only expected `console.log` calls.

### CS-03: Document every API route with OpenAPI

**Rule:** Every new or changed Express route in `api/src/routes` has a swagger-jsdoc `@swagger`
comment that describes its path, method, parameters, request body, and every status code it can
return. New or changed models in `api/src/models` have a matching `components/schemas` entry.

**Why:** The docs at `/api-docs` are generated from these comments, so an undocumented route is
invisible to the people who call the API.

**Compliant:** Follow `api/src/routes/branch.ts` and `api/src/models/branch.ts`. When a handler's
behavior changes (a new parameter or status code), the comment is updated in the same PR.

### CS-04: Correct HTTP status codes and safe errors

**Rule:** API handlers return the status code that matches the outcome, and error responses never
include stack traces, raw error objects, or other internal details.

**Why:** The frontend and the tests depend on status codes, and stack traces expose internals of a
public service.

**Compliant:** 200 for reads and updates, 201 with the created resource for creates, 204 with no
body for deletes, 400 for invalid input, 404 when the resource doesn't exist (for example
`res.status(404).send('Branch not found')`), and 500 with a generic message for unexpected
errors.

### CS-05: Test new and changed API routes

**Rule:** Every new or changed API route has Vitest and supertest tests in a `*.test.ts` file next
to the router, covering the success path and the main error path (such as 404 or 400).

**Why:** Routes are the API contract. CI runs these tests on every PR, so regressions get caught
before deploy.

**Compliant:** Follow `api/src/routes/branch.test.ts`: build a fresh Express app in `beforeEach`,
mount the router, reset the in-memory data, and assert on both the status code and the body.

### CS-06: No hardcoded secrets or environment-specific URLs

**Rule:** New or changed code and config don't contain secrets, tokens, passwords, keys, or
connection strings, and don't hardcode environment-specific URLs or hostnames (Azure, staging,
production, or Codespaces).

**Why:** This repository is public, so a committed secret is leaked the moment it's pushed. Hardcoded
URLs also break when the app moves between local, Codespaces, and Azure.

**Compliant:** The API reads configuration from environment variables (`process.env.PORT`,
`process.env.API_CORS_ORIGINS`). The frontend gets the API URL from runtime config through
`frontend/src/api/config.ts`. Localhost defaults for local development and obviously fake test data
are fine.

### CS-07: Typed React function components styled with Tailwind

**Rule:** New or changed React components are function components with typed props, styled with
Tailwind utility classes in `className` rather than inline `style` objects.

**Why:** It keeps the frontend consistent, keeps dark mode (`useTheme`) and spacing in one system,
and lets the compiler catch wrong props.

**Compliant:** Follow `ProductForm.tsx`: an `interface ProductFormProps` and
`export default function ProductForm({ ... }: ProductFormProps)`, with dark mode handled through
conditional classes. Inline `style` is fine only for values Tailwind can't express, such as the SVG
filter reference in `Welcome.tsx`. No class components.

### CS-08: Accessible UI

**Rule:** New or changed images have meaningful `alt` text, and every interactive control has an
accessible name.

**Why:** Keyboard and screen reader users need to be able to browse and order products too.

**Compliant:** Images use descriptive `alt` text (`alt={product.name}`), or `alt=""` when purely
decorative. Buttons have visible text or an `aria-label` (icon-only buttons always need one, like
the quantity buttons in `Products.tsx`). Form fields have a `<label htmlFor>` or `aria-label`, as
in `Login.tsx`. Clickable elements are `<button>`, `<a>`, or `Link`, not a `div` with `onClick`.
