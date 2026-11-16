# Checking Benchmark Results Using Continuous Integration

Benchmark was written with continuous integration in mind, and allows you to set up comparisons to validate builds. 

## Overview

Benchmark was developed to be invoked through command line options to support automation.

There are two approaches to checking benchmarks vs expected results with CI:

* Dynamic Comparative Analysis: Run a benchmark on the current branch and on the main branch, then compare the results.
* Static Threshold Validation: Run a benchmark on the current branch and compare it against a pre-established baseline or threshold.

Regardless of which approach you use, you can specify tolerance thresholds (both absolute and relative) that determine whether metrics from different runs should be considered equivalent. These thresholds are defined in Swift code alongside the actual benchmark.

The Dynamic Comparative Analysis approach offers the advantage of being resilient to environmental changes (such as toolchain and operating system updates). If your primary concern is detecting regressions in your own code rather than those introduced by toolchain or OS updates, this method is particularly useful. It doesn't require storing historical data, which can be both an advantage and a limitation.

The Static Threshold Validation approach involves maintaining a set of predefined performance thresholds against which new benchmark runs are compared. This method can significantly reduce build time for more complex setups. However, it necessitates periodic manual validation and updates of the baseline thresholds.

The `swift package benchmark baseline check` command exits with a non-zero status if performance degradations are detected when comparing a benchmark run against the established baseline.

### Baselines
A baseline captures a specific benchmark run and serves as a reference point for future comparisons or threshold updates.

### Static Thresholds
A threshold defines an acceptable performance value for a specific metric within a benchmark. It's used to validate subsequent baseline or benchmark runs when using static threshold validation.

### Comparison Methods

#### 1. Comparing Two Baselines (e.g., PR vs. main)
To check two previously stored baselines for deviations (taking tolerance thresholds specified into the code into account):
```bash
swift package benchmark baseline check main pull_request
```

#### 2. Comparing a Test Run Against Static Thresholds
To run all benchmarks and compare them against previously saved static thresholds (taking tolerance thresholds specified into the code into account):
```bash
swift package benchmark thresholds check
```

#### 3. Storing Static Thresholds
```bash
swift package --allow-writing-to-package-directory benchmark thresholds update
```

#### 4. Reading the Static Thresholds
```bash
swift package benchmark thresholds read
```

### Return Codes from checking thresholds (dynamic comparison or static comparison)
- 0: Check is exactly equal
- 2: Regressions detected
- 4: Only improvements detected

### Example GitHub CI Workflow from Vapor

Vapor have a nice example [for CI integration at GitHub](https://github.com/vapor/ci/blob/main/.github/workflows/run-benchmark.yml) which
can [be manually run like this](https://github.com/vapor/multipart-kit/blob/main/.github/workflows/benchmark.yml).

Sample output [can be found here](https://github.com/vapor/multipart-kit/pull/107#issuecomment-2629492189).

### Example: GitHub CI Workflow for Baseline Comparison

This workflow compares any pull request against the `main` branch, failing on regression. If the comparison is equal or favorable, it comments on the pull request with the results.

```yaml
name: Benchmark PR vs main

on:
  workflow_dispatch:
  pull_request:
    branches: [ main ]
  
jobs:
  benchmark-delta:

    runs-on: ${{ matrix.os }}
    continue-on-error: true
    permissions:
        issues: write
        pull-requests: write

    strategy:
      matrix:
        #os: [[Linux, benchmark-swift-latest, self-hosted]]
        os: [ubuntu-latest]

    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      # The jemalloc install steps below are only needed when benchmarking with Swift 6.2 or
      # earlier. On Swift 6.3+ the default malloc-interposer backend needs no system package.
      - name: Homebrew Mac
        if: ${{ runner.os == 'Macos' }}
        run: |
          echo "/opt/homebrew/bin:/usr/local/bin" >> $GITHUB_PATH
          brew install jemalloc

      - name: Ubuntu deps
        if: ${{ runner.os == 'Linux' }}
        run: |
          sudo apt-get install -y libjemalloc-dev

      - name: Git URL token override and misc
        run: |
          #git config --global url."https://ordo-ci:${{ secrets.CI_MACHINE_PAT }}@github.com".insteadOf "https://github.com"
          #/usr/bin/ordo-performance
          [ -d Benchmarks ] && echo "hasBenchmark=1" >> $GITHUB_ENV
          echo "/opt/homebrew/bin:/usr/local/bin" >> $GITHUB_PATH
      - name: Run benchmarks for PR branch
        if: ${{ env.hasBenchmark == '1' }}
        run: |
          swift package --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update pull_request --no-progress --quiet
      - name: Switch to branch 'main'
        if: ${{ env.hasBenchmark == '1' }}
        run: |
          git stash
          git checkout main
      - name: Run benchmarks for branch 'main'
        if: ${{ env.hasBenchmark == '1' }}
        run: |
          swift package --allow-writing-to-directory .benchmarkBaselines/ benchmark baseline update main --no-progress --quiet
      - name: Compare PR and main
        if: ${{ env.hasBenchmark == '1' }}
        id: benchmark
        run: |
          echo '## Summary' >> $GITHUB_STEP_SUMMARY
          echo $(date) >> $GITHUB_STEP_SUMMARY
          echo "exitStatus=1" >> $GITHUB_ENV
          swift package benchmark baseline check main pull_request --format markdown >> $GITHUB_STEP_SUMMARY
          echo '---' >> $GITHUB_STEP_SUMMARY
          swift package benchmark baseline compare main pull_request --no-progress --quiet --format markdown >> $GITHUB_STEP_SUMMARY
          echo "exitStatus=0" >> $GITHUB_ENV
        continue-on-error: true
      - if: ${{ env.exitStatus == '0' }}
        name: Pull request comment text success
        id: prtestsuccess
        run: |
          echo 'PRTEST<<EOF' >> $GITHUB_ENV
          echo "[Pull request benchmark comparison [${{ matrix.os }}] with 'main' run at $(date -Iseconds)](https://github.com/ordo-one/${{ github.event.repository.name }}/actions/runs/${{ github.run_id }})" >> $GITHUB_ENV
          echo 'EOF' >> $GITHUB_ENV
      - if: ${{ env.exitStatus == '1' }}
        name: Pull request comment text failure
        id: prtestfailure
        run: |
          echo 'PRTEST<<EOF' >> $GITHUB_ENV
          echo "[Pull request benchmark comparison [${{ matrix.os }}] with 'main' run at $(date -Iseconds)](https://github.com/ordo-one/${{ github.event.repository.name }}/actions/runs/${{ github.run_id }})" >> $GITHUB_ENV
          echo "_Pull request had performance regressions_" >> $GITHUB_ENV
          echo 'EOF' >> $GITHUB_ENV
      - name: Comment PR
        if: ${{ env.hasBenchmark == '1' }}
        uses: thollander/actions-comment-pull-request@v2
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          message: ${{ env.PRTEST }}
          comment_includes: "Pull request benchmark comparison [${{ matrix.os }}] with"
      - name: Exit with correct status
        run: |
          exit ${{ env.exitStatus }}
```

> Important: For reproducible and good comparable results, it is *highly* recommended to set up a private GitHub runner on a machine dedicated to performance benchmark runs.
