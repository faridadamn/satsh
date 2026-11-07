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
    if [ -f "$rc" ] && ! grep -q 'markas-path' "$rc"; then echo 'export PATH="$HOME/.local/bin:$PATH" # markas-path' >> "$rc"; fi
  done ;;
esac
if [ -d "$HOME/.hermes" ] && [ -f "$D/hermes-SKILL.md" ]; then
  mkdir -p "$HOME/.hermes/skills/markas"
  cp "$D/hermes-SKILL.md" "$HOME/.hermes/skills/markas/SKILL.md"
  echo "HERMES_SKILL_OK"
fi
# Hermes is optional: every probe below must tolerate "not found" under set -e.
HB=$(command -v hermes 2>/dev/null || bash -lc 'command -v hermes' 2>/dev/null </dev/null || true)
if [ -z "$HB" ]; then
  for p in "$HOME/.local/bin/hermes" "$HOME/.hermes/bin/hermes" /usr/local/bin/hermes; do
    if [ -x "$p" ]; then HB="$p"; break; fi
  done
fi
if [ -n "$HB" ]; then echo "HERMES_CLI_OK $HB"; fi
echo "MARKAS_OK $("$PY" "$D/markas.py" --version)"
