#!/usr/bin/env bash
set -euo pipefail

# Bring live $HOME changes back into the repo.
#   pull-home.sh            re-adopt tracked files whose symlink was replaced
#                           by a real file (e.g. by an atomic save)
#   pull-home.sh PATH...    move new files or directories under $HOME into
#                           the repo and symlink them

repo="${DOTFILES_DIR:-$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")}"
package="$repo/home"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  printf 'Run as your user, not root.\n' >&2
  exit 1
fi

if [ ! -d "$package" ]; then
  printf 'Missing home package: %s\n' "$package" >&2
  exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
  printf 'stow is not installed.\n' >&2
  exit 1
fi

adopt=()
new=()

if [ "$#" -eq 0 ]; then
  while IFS= read -r source; do
    rel="${source#$package/}"
    target="$HOME/$rel"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      continue
    fi
    if [ -L "$target" ]; then
      # Absolute links (e.g. made by hand with ln -s) are not owned by stow
      # and make it abort, so relink them the stow way.
      if [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ] \
        && [ "$(readlink "$target")" = "${source}" ]; then
        printf 'relink   %s (manual absolute symlink)\n' "$target"
        adopt+=("$rel")
      fi
      continue
    fi
    if [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
      continue
    fi
    if cmp -s "$source" "$target"; then
      printf 'relink   %s (identical)\n' "$target"
    else
      printf 'adopt    %s (live version replaces repo)\n' "$target"
      diff -u "$source" "$target" || true
    fi
    adopt+=("$rel")
  done < <(find "$package" -path '*/.git/*' -prune -o -type f -print | sort)
else
  for path in "$@"; do
    abs="$(realpath -s "$path")"
    rel="${abs#$HOME/}"
    if [ "$rel" = "$abs" ]; then
      printf 'Not under %s: %s\n' "$HOME" "$path" >&2
      exit 1
    fi
    if [ -L "$abs" ]; then
      printf 'Already a symlink: %s\n' "$abs" >&2
      exit 1
    fi
    if [ ! -e "$abs" ]; then
      printf 'Missing: %s\n' "$abs" >&2
      exit 1
    fi
    if [ -e "$package/$rel" ]; then
      printf 'Already in repo: %s (run without arguments instead)\n' "$rel" >&2
      exit 1
    fi
    printf 'new      %s -> %s\n' "$abs" "$package/$rel"
    new+=("$rel")
  done
fi

if [ "${#adopt[@]}" -eq 0 ] && [ "${#new[@]}" -eq 0 ]; then
  printf 'Nothing to pull: home is in sync.\n'
  exit 0
fi

printf '\nApply? Type YES to continue: '
read -r answer
if [ "$answer" != "YES" ]; then
  printf 'Aborted.\n'
  exit 1
fi

# Targets are moved to a backup instead of deleted, so a failing stow can be
# rolled back without losing anything.
backup_dir="$HOME/dotfiles-backups/pull-home-$(date +%Y%m%d-%H%M%S)"

for rel in "${adopt[@]}"; do
  if [ ! -L "$HOME/$rel" ]; then
    install -m "$(stat -c %a "$HOME/$rel")" "$HOME/$rel" "$package/$rel"
  fi
  mkdir -p "$backup_dir/$(dirname "$rel")"
  mv "$HOME/$rel" "$backup_dir/$rel"
done

for rel in "${new[@]}"; do
  mkdir -p "$(dirname "$package/$rel")"
  mv "$HOME/$rel" "$package/$rel"
done

if ! stow --verbose --restow --dir "$repo" --target "$HOME" home; then
  printf '\nstow failed: rolling back.\n' >&2
  for rel in "${adopt[@]}"; do
    mv "$backup_dir/$rel" "$HOME/$rel"
  done
  for rel in "${new[@]}"; do
    mv "$package/$rel" "$HOME/$rel"
  done
  printf 'Restored. Fix the conflicts above and run again.\n' >&2
  exit 1
fi

printf 'Home pulled. Previous targets saved in %s\n' "$backup_dir"
printf 'Review with: git -C %s status\n' "$repo"
