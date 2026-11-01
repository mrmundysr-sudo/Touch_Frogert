#!/bin/bash
# Parse-check every GDScript in the project. Usage: tools/check_scripts.sh [godot-binary]
G=${1:-godot}
fail=0
for f in $(find src tools main.gd -name '*.gd' 2>/dev/null); do
  out=$($G --headless --path . --check-only -s "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error" | head -3)
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
exit $fail
