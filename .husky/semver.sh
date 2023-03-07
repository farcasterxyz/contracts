#!/bin/sh
# rusty-hook
# version 0.11.2

isGreaterThanEqualToMinimumVersion() {
  currentVersion=${1}
  minimumMajor=${2}
  minimumMinor=${3}
  minimumPatch=${4}
  allowPrerelease=${5}

  oldIFS=${IFS}
  IFS="."
  # shellcheck disable=SC2086
  set -- ${currentVersion}
  currentMajor=${1}
  currentMinor=${2}
  suffix=${3}
  IFS="-"
  # shellcheck disable=SC2086
  set -- ${suffix}
  currentPatch=${1}
  currentPre=${2}
  IFS=${oldIFS}

  # shellcheck disable=SC2086
  if [ ${currentMajor} -gt ${minimumMajor} ]; then
    return 0
  elif [ ${currentMajor} -lt ${minimumMajor} ]; then
    return 1
  else
    # shellcheck disable=SC2086
    if [ ${currentMinor} -gt ${minimumMinor} ]; then
      return 0
    elif [ ${currentMinor} -lt ${minimumMinor} ]; then
      return 2
    else
      # shellcheck disable=SC2086
      if [ ${currentPatch} -gt ${minimumPatch} ]; then
        return 0
      elif [ ${currentPatch} -lt ${minimumPatch} ]; then
        return 3
      else
        if [ -z "${currentPre}" ]; then
          return 0
        elif [ "${allowPrerelease}" != "true" ]; then
          return 4
        fi
      fi
    fi
  fi
}
