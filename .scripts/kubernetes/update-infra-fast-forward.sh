#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="${INFRA_EXTERNAL_DIR:-/root/infra-external}"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

[[ -d "${repo_dir}/.git" ]] || fail "${repo_dir} is not an infra-external clone"

machine_drift="$(git -C "${repo_dir}" status --porcelain --untracked-files=all)"
[[ -z "${machine_drift}" ]] ||
  fail "machine-local drift exists; refusing to update or overwrite it"

upstream="$(git -C "${repo_dir}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
[[ -n "${upstream}" ]] || fail "the current branch has no configured upstream"

git -C "${repo_dir}" fetch
local_head="$(git -C "${repo_dir}" rev-parse HEAD)"
upstream_head="$(git -C "${repo_dir}" rev-parse "${upstream}")"

if [[ "${local_head}" == "${upstream_head}" ]]; then
  printf "infra-external is already at %s\n" "${upstream_head}"
  exit 0
fi

git -C "${repo_dir}" merge-base --is-ancestor "${local_head}" "${upstream_head}" ||
  fail "local history diverged from ${upstream}; refusing a reset or non-fast-forward update"

git -C "${repo_dir}" merge --ff-only "${upstream}"
updated_head="$(git -C "${repo_dir}" rev-parse HEAD)"
[[ "${updated_head}" == "${upstream_head}" ]] ||
  fail "fast-forward verification failed"
printf "infra-external fast-forwarded to %s\n" "${updated_head}"
