# Example Files for Binary Repos

This directory contains template files to copy to each binary repo you create.

## Setup Instructions

For each Swift package you want to mirror as binaries:

### 1. Create the binary repo

Create a new repo at `github.com/swift-bins/{owner}_{name}`

For example, to mirror `https://github.com/onevcat/Kingfisher`:
- Create repo: `github.com/swift-bins/onevcat_Kingfisher`

### 2. Copy configuration

Copy `binify-config.json` to the root of your new repo and edit it:

```json
{
    "source_repo": "https://github.com/onevcat/Kingfisher.git"
}
```

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
