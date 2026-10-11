#!/usr/bin/env bash
#
# The sysexits(3) codes for each way a command here fails. A shell has no
# header to read them from, so they're copied, under the man page's names.
# Exit 1 isn't among them, because a check exits 1 on a finding.
# shellcheck disable=SC2034  # the commands that source this use them

readonly EX_USAGE=64
readonly EX_NOINPUT=66
readonly EX_UNAVAILABLE=69
readonly EX_SOFTWARE=70
readonly EX_CANTCREAT=73
readonly EX_IOERR=74
readonly EX_CONFIG=78
