#!/bin/sh
# Installs markas for the current user: ~/.markas/markas.py + ~/.local/bin/markas (+ Hermes skill if Hermes is here).
set -e
D="${MARKAS_HOME:-$HOME/.markas}"
mkdir -p "$D" "$HOME/.local/bin"
chmod 700 "$D"
PY=$(command -v python3 || true)
[ -n "$PY" ] || { echo "ERROR: python3 ga ada di server"; exit 1; }
cat > "$HOME/.local/bin/markas" <<WRAP
#!/bin/sh
exec "$PY" "$D/markas.py" "\$@"
WRAP
chmod +x "$HOME/.local/bin/markas" "$D/markas.py"
"$PY" "$D/markas.py" init
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  for rc in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -f "$rc" ] && ! grep -q 'markas-path' "$rc" && echo 'export PATH="$HOME/.local/bin:$PATH" # markas-path' >> "$rc"
  done ;;
esac
if [ -d "$HOME/.hermes" ] && [ -f "$D/hermes-SKILL.md" ]; then
  mkdir -p "$HOME/.hermes/skills/markas"
  cp "$D/hermes-SKILL.md" "$HOME/.hermes/skills/markas/SKILL.md"
  echo "HERMES_SKILL_OK"
fi
HB=$(command -v hermes 2>/dev/null || bash -lc 'command -v hermes' 2>/dev/null </dev/null)
[ -z "$HB" ] && for p in "$HOME/.local/bin/hermes" "$HOME/.hermes/bin/hermes" /usr/local/bin/hermes; do [ -x "$p" ] && HB="$p" && break; done
[ -n "$HB" ] && echo "HERMES_CLI_OK $HB"
echo "MARKAS_OK $("$PY" "$D/markas.py" --version)"
