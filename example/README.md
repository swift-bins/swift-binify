# Example Files for Binary Repos

This directory contains template files to copy to each binary repo you create.

## Setup Instructions

For each Swift package you want to mirror as binaries:

### 1. Create the binary repo

Create a new repo. You have two naming options:

**Option A: With owner prefix (default)**
- Repo: `github.com/swift-bins/onevcat_Kingfisher`
- Set `requires_owner_prefix: true` in config
- Users must update their `.product(name:package:)` references

**Option B: Without owner prefix (simpler for users)**
- Repo: `github.com/swift-bins/Kingfisher`
- Set `requires_owner_prefix: false` in config
- Users only update the package URL, no other changes needed
- Only works if the package name is unique across all your binary repos

### 2. Copy configuration

Copy `binify-config.json` to the root of your new repo and edit it:

```json
{
    "source_repo": "https://github.com/onevcat/Kingfisher.git",
    "requires_owner_prefix": true
}
```

#### Configuration options

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `source_repo` | Yes | - | URL of the source repo to build |
| `requires_owner_prefix` | No | `true` | If `true`, repo is named `swift-bins/owner_repo`. If `false`, repo is named `swift-bins/repo` (simpler, but package name must be unique) |

When `requires_owner_prefix` is `false`:
- Name your repo just `swift-bins/Kingfisher` instead of `swift-bins/onevcat_Kingfisher`
- Users don't need to change their `.product(name:package:)` references

### 3. Copy the workflow

Copy `build-binary.yml` to `.github/workflows/build-binary.yml` in your repo.

### 4. Enable GitHub Actions

Make sure GitHub Actions are enabled for your repository.

### 5. (Optional) Set up PAT for self-updating workflow

The workflow can automatically update itself from swift-binify. This requires a Personal Access Token (PAT) because `GITHUB_TOKEN` cannot modify workflow files.

**To enable self-updating:**
1. In each binary repo, go to **Settings → Secrets and variables → Actions**
2. Click "New repository secret"
   - **Name**: `WORKFLOW_TOKEN`
   - **Secret**: Paste the swift-bins PAT
3. Click "Add secret"

If you skip this step, the workflow will still work but won't self-update.

### 6. Trigger the first build

Either:
- Wait for the nightly run (2 AM UTC)
- Manually trigger via Actions tab with optional tag input

## What happens

The workflow will:
1. Clone this tool (swift-binify) to get the latest version
2. Self-update its own workflow file (if `WORKFLOW_TOKEN` secret is set)
3. Fetch tags from the source repo
4. Build xcframeworks using swift-binify
5. Create a GitHub Release with zipped xcframeworks
6. Commit Package.swift, LICENSE, and README to the repo

## Self-updating

If you set up the `WORKFLOW_TOKEN` secret, the workflow automatically updates itself from this tool's example directory on each run. This means improvements propagate to all binary repos automatically.

Without the PAT, you'll need to manually copy updated workflows from swift-binify.
