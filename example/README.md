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

### 5. Trigger the first build

Either:
- Wait for the nightly run (2 AM UTC)
- Manually trigger via Actions tab with optional tag input

## What happens

The workflow will:
1. Clone this tool (swift-binify) to get the latest version
2. Self-update its own workflow file from the example directory
3. Fetch tags from the source repo
4. Build xcframeworks using swift-binify
5. Create a GitHub Release with zipped xcframeworks
6. Commit Package.swift, LICENSE, and README to the repo

## Self-updating

After the first run, the workflow automatically updates itself from this tool's example directory on each subsequent run. This means improvements to the workflow propagate to all binary repos automatically.
