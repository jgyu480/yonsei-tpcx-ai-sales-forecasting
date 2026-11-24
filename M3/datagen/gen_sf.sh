#!/bin/bash
# Generate TPCx-AI data for UC03/UC08 with the kit's PDGF, on x86 Linux + Java 8 (no Docker).
#   M3/datagen/gen_sf.sh <SF>      -> $OUT_ROOT/sf<SF>/{training,serving,scoring}
# The three PDGF commands are copied unchanged from M2/README.md section 3 (same seeds/options as the
# kit driver, driver/tpcxai-driver/data_generation.py). Only the paths (J, KIT, R) are filled in here.
# SF is the PDGF -sf value (integer). Scoring is always -sf 1, seed 1234 + SF.
# Running this accepts the PDGF license (lib/pdgf/LICENSE.txt), like the kit's first start.
# Overridable: J (java 8 binary), KIT (tpcx-ai-v2.0.0 dir), OUT_ROOT (output root, local disk).
set -euo pipefail
SF=${1:?usage: M3/datagen/gen_sf.sh <SF>}
[[ "$SF" =~ ^[0-9]+$ ]] || { echo "SF must be an integer (scoring seed is 1234 + SF)"; exit 1; }
J=${J:-$(ls -d "$HOME"/Applications/m3/jdk8u*/bin/java | head -1)}
KIT=${KIT:-$HOME/Applications/m3/tpcx-ai-v2.0.0}
OUT_ROOT=${OUT_ROOT:-$HOME/Works_ub/m3data/data}
R=$OUT_ROOT/sf$SF
if [ -d "$R" ] && [ -n "$(ls -A "$R" 2>/dev/null)" ]; then echo "$R is not empty; remove it first"; exit 1; fi

"$J" -version 2>&1 | head -2
echo "kit=$KIT  SF=$SF  -> $R"
mkdir -p "$R/training" "$R/serving" "$R/scoring"

# --- M2/README.md section 3 (unchanged) ---
cd "$KIT/data-gen"
O="-l config/tpcxai-schema.xml -l config/tpcxai-generation.xml -ns"
T="order lineitem product store_dept"
run() { printf '\nYES\n' | $J -Djava.awt.headless=true -Xmx4g -jar ../lib/pdgf/pdgf.jar $O "$@"; }
echo "[$(date '+%F %T')] training start"
run -sf $SF -sp MY_SEED 1234 -sp includeLabels 1.0 -sp TTVF 1.0 -s $T -output "\"$R/training/\""
echo "[$(date '+%F %T')] serving start"
run -sf $SF -sp SF_TRAINING $SF -sp MY_SEED 1235 -sp includeLabels 0.0 -sp TTVF 0.1 -s $T -output "\"$R/serving/\""
echo "[$(date '+%F %T')] scoring start"
run -sf 1 -sp SF_TRAINING $SF -sp MY_SEED $((1234 + SF)) -sp includeLabels 2.0 -sp TTVF 0.1 -s $T order_weekly_sales -output "\"$R/scoring/\""
echo "[$(date '+%F %T')] done"
# ------------------------------------------

cd "$R" && find . -name '*.csv' | sort | xargs wc -l
