# Linux automatic low system load suspend utility

Utility to automatically suspend the system with low load on Linux. This is useful for saving power on hosts that will temporarily be under heavy load, but cannot automate the suspend process due to the nature of the workload, such as running a Windows build in a guest VM.

<https://gitlab.com/brlin/linux-low-load-autosuspend>  
[![The GitLab CI pipeline status badge of the project's `main` branch](https://gitlab.com/brlin/linux-low-load-autosuspend/badges/main/pipeline.svg?ignore_skipped=true "Click here to check out the comprehensive status of the GitLab CI pipelines")](https://gitlab.com/brlin/linux-low-load-autosuspend/-/pipelines) [![GitHub Actions workflow status badge](https://github.com/brlin-tw/linux-low-load-autosuspend/actions/workflows/check-potential-problems.yml/badge.svg "GitHub Actions workflow status")](https://github.com/brlin-tw/linux-low-load-autosuspend/actions/workflows/check-potential-problems.yml) [![pre-commit enabled badge](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white "This project uses pre-commit to check potential problems")](https://pre-commit.com/) [![REUSE Specification compliance badge](https://api.reuse.software/badge/gitlab.com/brlin/linux-low-load-autosuspend "This project complies to the REUSE specification to decrease software licensing costs")](https://api.reuse.software/info/gitlab.com/brlin/linux-low-load-autosuspend)  
\#linux \#suspend-to-ram \#power-management \#utility \#bash

## Prerequisites

This utility requires a Linux system with the following software installed and their commands available in the command search PATHs:

* [GNU AWK (gawk)](https://www.gnu.org/software/gawk/)  
  For parsing system load information from `/proc/loadavg`.
* [GNU Bash](https://www.gnu.org/software/bash/)  
  Provides the runtime where the monitoring program runs in.
* [GNU bc](https://www.gnu.org/software/bc/)  
  For floating-point arithmetic calculations of load thresholds.
* [GNU coreutils](https://www.gnu.org/software/coreutils/)  
  Provides `head`, `sort`, `tee`, `uniq`, and `wc` commands for text processing.
* [GNU grep](https://www.gnu.org/software/grep/)  
  For filtering CPU information from `/proc/cpuinfo`.
* [systemd](https://systemd.io/)  
  Provides the `systemctl` command for system suspend functionality.

The monitoring program must be run as a superuser (root) user, as it needs to call the `systemctl suspend` command to suspend the system.

## Usage

Refer to the following instructions to use this utility:

1. Download the release archive from [the Releases page](https://gitlab.com/brlin/linux-low-load-autosuspend/-/releases).
1. Extract the release archive to a directory of your choice.
1. Launch a text terminal.
1. In the text terminal, run the following command _as root_ to start the automatic suspend monitoring process:

    ```bash
    sudo /path/to/linux-low-load-autosuspend-X.Y.Z/suspend-linux-when-low-load.sh
    ```

   Replace the `X.Y.Z` placeholder text to the actual version number of the release archive you downloaded.

   You can customize the monitoring behavior by using the environment variables documented in [the "Environment variables that can influence the behavior of the utility" chapter](#environment-variables-that-can-influence-the-behavior-of-the-utility)

## Environment variables that can influence the behavior of the utility

The following environment variables can be set to influence the behavior of the utility:

### LOAD\_THRESHOLD\_RATIO

The _average_ system load ratio threshold to trigger the suspend process, it is a ratio of the number of CPU _physical_ cores on the system(not accounting virtual cores as a result of hyper-threading-like mechanisms).  If the average system load is below this threshold, the system will be suspended.

The default value is `0.5`, which means for a system with 8 physical CPU cores and 16 total threads, the average system load threashold is `4.0` (8 * 0.5).

### CHECK\_INTERVAL

Time (in seconds) between each load check.

**Default value:** `300` (5 minutes)

### CONSECUTIVE\_CHECKS\_REQUIRED

How many consecutive "low load" check results should the monitoring utility give the verict that the system's load is low.  This prevents accidental suspend during momentary dips.

**Default value:** `3`

## References

The following materials are referenced during the development of this project:

* ["How do I make a Linux system go to sleep after the average system load is under a certain threshold?" LLM response - HackMD](https://hackmd.io/@brlin/HJKJ01Dfgg)  
  Provides the initial implementation.

## Licensing

Unless otherwise noted([comment headers](https://reuse.software/spec-3.3/#comment-headers)/[REUSE.toml](https://reuse.software/spec-3.3/#reusetoml)), this product is licensed under [the 3.0 version of the GNU Affero General Public License](https://www.gnu.org/licenses/agpl-3.0.en.html), or any of its more recent versions of your preference.

This work complies to [the REUSE Specification](https://reuse.software/spec/), refer to the [REUSE - Make licensing easy for everyone](https://reuse.software/) website for info regarding the licensing of this product.
