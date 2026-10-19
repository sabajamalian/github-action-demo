# OctoCAT Supply

OctoCAT Supply is a small supply chain web app: a React + Vite + Tailwind frontend and an Express + TypeScript API with in-memory sample data and Swagger docs. This repository uses it as a target for GitHub Actions demos.

The application code comes from [colindembovsky/octocat-supply-copilot-demo](https://github.com/colindembovsky/octocat-supply-copilot-demo). Only the app is kept here. The demo scripts, dev container, docs, and original workflows were removed.

## Run it locally

You need Node.js 22 (18 or later works).

```bash
npm install
npm run dev
```

- API: http://localhost:3000 (Swagger UI at http://localhost:3000/api-docs)
- Frontend: http://localhost:5137

| Script | What it does |
| --- | --- |
| `npm run build` | Type-checks and builds the API and the frontend |
| `npm test` | Runs the API unit tests (Vitest) |
| `npm run test:coverage` | Runs the unit tests with coverage |
| `npm run lint` | Runs ESLint in both workspaces |
| `npm run format` / `npm run format:check` | Formats or checks the code with Prettier |

To run the containers, build from the repository root:

```bash
docker build -f api/Dockerfile -t octacat-api .
docker build -f frontend/Dockerfile -t octacat-web .
docker run -d -p 3000:3000 octacat-api
docker run -d -p 8080:80 -e API_HOST=localhost -e API_PORT=3000 -e API_PROTOCOL=http octacat-web
```

## Workflows

| Workflow | File | Runs on | What it does |
| --- | --- | --- | --- |
| Deploy to Azure | [`deploy.yml`](.github/workflows/deploy.yml) | Push to `main`, or manually | Builds both images, pushes them to Azure Container Registry, updates the two Container Apps, and smoke tests the live URLs |
| CI | [`ci.yml`](.github/workflows/ci.yml) | Pull requests | Build and type-check, unit tests with coverage, ESLint and Prettier checks, and a container build with a smoke test |
| Copilot coding standards | [`copilot-coding-standards.yml`](.github/workflows/copilot-coding-standards.yml) | Manually, for a PR number you enter | Runs the Copilot CLI to check a pull request against [`.github/coding-standards.md`](.github/coding-standards.md) and comments on the PR with each standard marked Met, Not met, or N/A |
| Weekly summary | [`weekly-summary.md`](.github/workflows/weekly-summary.md) | Fridays at 9:00 AM US Central, or manually | A [GitHub Agentic Workflow](https://github.github.com/gh-aw/) that opens an issue summarizing the week's commits, pull requests, issues, and deployments, and closes the previous week's issue |

### Deploy to Azure

Merge a pull request to `main` (or run the workflow from the Actions tab). The job runs in the `production` environment, and that environment only accepts deployments from `main`. The run summary links to the live site.

The workflow signs in to Azure with OpenID Connect, so there are no Azure passwords or keys in the repository. The managed identity it uses only trusts tokens issued for this repository's `production` environment.

### CI

Open a pull request. The four jobs show up as checks on the PR. To make them required, add them to a branch protection rule or ruleset for `main`.

### Copilot coding standards

This workflow isn't triggered automatically. To try it:

1. Open a pull request.
2. Go to **Actions > Copilot coding standards > Run workflow** and enter the PR number.
3. The workflow comments on the PR with a table of standards and a final `PASS` or `FAIL`. It fails the run when a standard isn't met (set `FAIL_ON_VIOLATION` to `"false"` to only report).

To run it on every pull request, uncomment the `pull_request` trigger at the top of the file. Fork PRs are skipped.

It authenticates the Copilot CLI with the workflow's own token through the `copilot-requests: write` permission, so it doesn't need a personal access token. Copilot usage is billed to the repository owner, and each run is capped with `MAX_AI_CREDITS`. The CLI can read files but can't run shell commands or write files.

Edit [`.github/coding-standards.md`](.github/coding-standards.md) to change the standards.

### Weekly summary

The workflow source is [`weekly-summary.md`](.github/workflows/weekly-summary.md), and Actions runs the compiled [`weekly-summary.lock.yml`](.github/workflows/weekly-summary.lock.yml). After editing the markdown, recompile it with the [gh aw](https://github.com/github/gh-aw) CLI and commit both files:

```bash
gh extension install github/gh-aw
gh aw compile weekly-summary
```

Run it on demand from the Actions tab, or with `gh aw run weekly-summary`. The new issue is labeled `weekly-summary`.

## Azure

The app runs on Azure Container Apps in the `rg-octacat` resource group. The registry and identities are in Central US; the Container Apps environment is in West US 3 because Central US had no Container Apps capacity when this was set up.

| Resource | Purpose |
| --- | --- |
| Container registry (Basic) | Stores the `octacat-api` and `octacat-web` images |
| Container Apps environment `cae-octacat-westus3` | Hosts both apps |
| Container apps `octacat-api` and `octacat-web` | Scale between 0 and 1 replicas, so the first request after an idle period is slow |
| Managed identity `id-octacat-acrpull` | Lets the apps pull images from the registry |
| Managed identity `id-octacat-github` | Used by the deploy workflow through a federated credential for the `production` environment |

[`infra/setup-azure.sh`](infra/setup-azure.sh) creates all of this and sets the repository secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`), the `ACR_NAME` variable, and the `production` environment. It's safe to re-run. You need the Azure CLI signed in to the subscription and the GitHub CLI signed in as a repository admin.

```bash
bash infra/setup-azure.sh
```

To remove everything: `az group delete --name rg-octacat --subscription <subscription-id>`.

## Who can run the workflows

The repository is public, but only the owner can start a workflow run:

- Pushing to the repository, running a workflow manually, and re-running jobs all need write access. Only the owner has it.
- Workflows for pull requests from forks don't start until the owner approves them (**Settings > Actions > General > Approval for running fork pull request workflows from contributors** is set to require approval for all external contributors).
- The default `GITHUB_TOKEN` is read-only, and each workflow asks only for the permissions it needs.
- No workflow uses `pull_request_target`, `issue_comment`, or other triggers that outside users can fire.

## License

MIT. See [LICENSE](LICENSE).
