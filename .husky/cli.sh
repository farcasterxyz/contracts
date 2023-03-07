#!/bin/sh
# rusty-hook
# version 0.11.2

minimumMajorCliVersion=0
minimumMinorCliVersion=11
minimumPatchCliVersion=0
allowPrereleaseCliVersion=false
noConfigFileExitCode=3

upgradeRustyHookCli() {
  echo "Upgrading rusty-hook cli..."
  echo "This may take a few seconds..."
  cargo install --force rusty-hook >/dev/null 2>&1
}

installRustyHookCli() {
  echo "Finalizing rusty-hook configuration..."
  echo "This may take a few seconds..."
  cargo install rusty-hook >/dev/null 2>&1
}

ensureMinimumRustyHookCliVersion() {
  currentVersion=$(rusty-hook -v)
  isGreaterThanEqualToMinimumVersion "${currentVersion}" ${minimumMajorCliVersion} ${minimumMinorCliVersion} ${minimumPatchCliVersion} ${allowPrereleaseCliVersion} >/dev/null 2>&1
  versionCompliance=$?
  if [ ${versionCompliance} -gt 0 ]; then
    upgradeRustyHookCli || true
  fi
}

handleRustyHookCliResult() {
  rustyHookExitCode=${1}
  hookName=${2}

  # shellcheck disable=SC2086
  if [ ${rustyHookExitCode} -eq 0 ]; then
    exit 0
  fi

  # shellcheck disable=SC2086
  if [ ${rustyHookExitCode} -eq ${noConfigFileExitCode} ]; then
    if [ "${hookName}" = "pre-commit" ]; then
      echo "rusty-hook git hooks are configured, but no config file was found"
      echo "In order to use rusty-hook, your project must have a config file"
      echo "See https://github.com/swellaby/rusty-hook#configure for more information about configuring rusty-hook"
      echo
      echo "If you were trying to remove rusty-hook, then you should also delete the git hook files to remove this warning"
      echo "See https://github.com/swellaby/rusty-hook#removing-rusty-hook for more information about removing rusty-hook from your project"
      echo
    fi
    exit 0
  else
    echo "Configured hook command failed"
    echo "${hookName} hook rejected"
    # shellcheck disable=SC2086
    exit ${rustyHookExitCode}
  fi
}

# shellcheck source=src/hook_files/semver.sh
. "$(dirname "$0")"/semver.sh
