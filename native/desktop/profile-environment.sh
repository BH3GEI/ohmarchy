# Route D: login shells (omarchy -c, ssh, a TTY) get the same environment as the
# desktop session, which ohdisplay.lua reads from these files (there is no systemd
# to apply environment.d). KEY=VALUE lines only; comments and blanks are skipped.
for f in "$HOME"/.config/environment.d/*.conf; do
    [ -r "$f" ] || continue
    while IFS= read -r l; do
        case $l in '' | '#'*) continue ;; *=*) export "${l%%=*}=${l#*=}" ;; esac
    done < "$f"
done
unset f l
