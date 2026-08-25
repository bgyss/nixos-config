# nixpkgs pins tmuxPlugins.resurrect to unstable-2022-05-01 -- bump to the
# latest upstream commit (project has had no releases; master is the
# reference point) so restore-time bugfixes since then are picked up.
#
# Also patch scripts/save.sh: tmux's #{pane_current_path} intermittently (and
# rarely -- observed a handful of times across weeks of 5-minute continuum
# auto-saves) misreports "/" for a pane on macOS, even though `lsof -d cwd`
# on the same pid at the same moment confirms the pane's *real* cwd is
# unaffected. Because resurrect saves whatever tmux reports, and restore
# recreates the pane with `-c /`, one transient misreport becomes permanent:
# every following auto-save faithfully re-captures the now-genuinely-"/"
# pane forever. Fix: cache the last known-good (non-"/") dir per
# session:window:pane and fall back to it whenever tmux reports "/", so a
# one-off glitch self-heals within a single save cycle instead of getting
# baked in.
final: prev: {
  tmuxPlugins = prev.tmuxPlugins // {
    resurrect = prev.tmuxPlugins.resurrect.overrideAttrs (old: {
      version = "0-unstable-2023-03-06";
      src = prev.fetchFromGitHub {
        owner = "tmux-plugins";
        repo = "tmux-resurrect";
        rev = "cff343cf9e81983d3da0c8562b01616f12e8d548";
        fetchSubmodules = true;
        hash = "sha256-2ZM23RQps2XO2OYX9NTZj5yIUZEv4ggYzjrJ9RxxLLg=";
      };
      postInstall = (old.postInstall or "") + ''
                save_sh="$out/share/tmux-plugins/resurrect/scripts/save.sh"

                # Insert helpers for the last-known-good-dir cache right after the
                # preamble, before the rest of save.sh's function definitions.
                sed -i '/^source "\$CURRENT_DIR\/spinner_helpers.sh"$/a\
        \
        # See overlay comment: work around tmux occasionally misreporting "/" for\
        # #{pane_current_path}. Cache is a tab-separated\
        # session:window:pane_index -> dir map, one entry per line.\
        good_dir_cache_file() {\
        	echo "$(resurrect_dir)/.last_good_dirs.tsv"\
        }\
        \
        lookup_good_dir() {\
        	local key="$1"\
        	local cache_file="$(good_dir_cache_file)"\
        	[ -f "$cache_file" ] || return 1\
        	awk -F"\\t" -v k="$key" '"'"'$1 == k { print $2; found=1 } END { exit !found }'"'"' "$cache_file"\
        }\
        \
        remember_good_dir() {\
        	local key="$1" dir="$2"\
        	local cache_file="$(good_dir_cache_file)"\
        	mkdir -p "$(dirname "$cache_file")"\
        	touch "$cache_file"\
        	awk -F"\\t" -v k="$key" '"'"'$1 != k'"'"' "$cache_file" > "$cache_file.tmp" || true\
        	printf '"'"'%s\\t%s\\n'"'"' "$key" "$dir" >> "$cache_file.tmp"\
        	mv "$cache_file.tmp" "$cache_file"\
        }' "$save_sh"

                # In dump_panes, right after the space-escaping line, fall back to
                # the cached good dir when tmux reported "/", and otherwise update
                # the cache with the freshly observed good dir.
                sed -i "/dir=\\\$(echo \\\$dir | sed 's\\/ \\/\\\\\\\\ \\/')/a\\
        \\t\\t\\tpane_key=\"\$session_name:\$window_number:\$pane_index\"\\
        \\t\\t\\tif [ \"\$dir\" = \":/\" ]; then\\
        \\t\\t\\t\\tcached_dir=\"\$(lookup_good_dir \"\$pane_key\")\"\\
        \\t\\t\\t\\t[ -n \"\$cached_dir\" ] \\&\\& dir=\"\$cached_dir\"\\
        \\t\\t\\telse\\
        \\t\\t\\t\\tremember_good_dir \"\$pane_key\" \"\$dir\"\\
        \\t\\t\\tfi" "$save_sh"
      '';
    });
  };
}
