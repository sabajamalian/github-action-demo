# OctoCAT Supply

A small supply-chain app with a React frontend and an Express API. This repository demonstrates four GitHub Actions workflows.

**Try the app:** [Web app](https://octacat-web.ashymushroom-3ae4a345.westus3.azurecontainerapps.io) · [API docs](https://octacat-api.ashymushroom-3ae4a345.westus3.azurecontainerapps.io/api-docs)

## Run locally

Requires Node.js 22.

```bash
npm install
npm run dev
```

The frontend runs at http://localhost:5137 and the API at http://localhost:3000.

## GitHub Actions demos

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [CI](.github/workflows/ci.yml) | Pull request | Builds the app, runs tests and style checks, and smoke-tests the containers. |
| [Deploy to Azure](.github/workflows/deploy.yml) | Push to `main` or manual | Publishes the app to Azure Container Apps. |
| [Copilot coding standards](.github/workflows/copilot-coding-standards.yml) | Manual | Reviews a pull request against the [coding standards](.github/coding-standards.md) and posts a report. |
| [Weekly summary](.github/workflows/weekly-summary.md) | Fridays at 9 AM Central or manual | Creates an issue summarizing repository activity. |

To try the Copilot review, open **Actions > Copilot coding standards > Run workflow** and enter a pull request number. To run the weekly summary, choose **Actions > Weekly repository summary > Run workflow**.

The weekly summary's `.lock.yml` is generated from its `.md` source by the [GitHub Agentic Workflows CLI](https://github.com/github/gh-aw).

## About

The app is adapted from [colindembovsky/octocat-supply-copilot-demo](https://github.com/colindembovsky/octocat-supply-copilot-demo). It runs in Azure; the deployment workflow uses OpenID Connect rather than stored Azure credentials.

This repository is public. Only the repository owner has write access, and fork pull request workflows require the owner's approval.

MIT licensed. See [LICENSE](LICENSE).
