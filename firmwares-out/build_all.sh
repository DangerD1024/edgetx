#!/usr/bin/env bash
# Build EdgeTX firmware (with USB_CHANNELS_MODE) for every Radiomaster and
# Jumper target, in a chosen UI language. Output filenames carry the
# language as a suffix so EN and UA builds can coexist:
#   firmwares-out/<board>-<lang>.bin
# Per-target logs go to firmwares-out/logs/<board>-<lang>.log
#
# Usage:
#   LANG=ua ./build_all.sh        # build Ukrainian (default)
#   LANG=en ./build_all.sh        # build English
#   ./build_all.sh                # → ua
#
# Boards already produced for the requested language are skipped, so
# re-running the script after a partial / failed run only retries what
# is missing.
set -u

EDGETX="/home/dangerd/Documents/Work/edgetx"
OUT="$EDGETX/firmwares-out"
LOGS="$OUT/logs"
TOOLCHAIN="/home/dangerd/Firmwares/betaflight/tools/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin"
VENV="$EDGETX/.venv"

LANG="${LANG:-ua}"
LANG="${LANG,,}"
case "$LANG" in
  ua) TR=UA ;;
  en) TR=EN ;;
  *) echo "[build_all] unsupported LANG=$LANG (use 'ua' or 'en')"; exit 2 ;;
esac

echo "[build_all] LANG=$LANG TRANSLATIONS=$TR"

# Format: <build-target-name> <-DPCB=...> <extra-options...>
# Names match radio/util/build-firmware.py / tools/build-common.sh.
# LTO is enabled for the small (512 KB FLASH) X7-class boards because UA
# translations + Cyrillic font tip them over the limit by a few KB without it.
declare -a TARGETS=(
  # ---- Radiomaster ----
  "boxer        -DPCB=X7  -DPCBREV=BOXER"
  "gx12         -DPCB=X7  -DPCBREV=GX12"
  "mt12         -DPCB=X7  -DPCBREV=MT12"
  "pocket       -DPCB=X7  -DPCBREV=POCKET   -DHELI=OFF -DLUA_MIXER=OFF"
  "tx12mk2      -DPCB=X7  -DPCBREV=TX12MK2  -DHELI=OFF -DLUA_MIXER=OFF"
  "zorro        -DPCB=X7  -DPCBREV=ZORRO    -DHELI=OFF -DLUA_MIXER=OFF"
  "tx15         -DPCB=TX15"
  "tx16s        -DPCB=X10 -DPCBREV=TX16S"
  "tx16smk3     -DPCB=TX16SMK3"
  # ---- Jumper ----
  "bumblebee    -DPCB=X7  -DPCBREV=BUMBLEBEE -DHELI=OFF -DLUA_MIXER=OFF"
  "t12max       -DPCB=X7  -DPCBREV=T12MAX    -DHELI=OFF -DLUA_MIXER=OFF"
  "t14          -DPCB=X7  -DPCBREV=T14       -DHELI=OFF -DLUA_MIXER=OFF"
  "t20          -DPCB=X7  -DPCBREV=T20       -DHELI=OFF -DLUA_MIXER=OFF"
  "t20v2        -DPCB=X7  -DPCBREV=T20V2     -DHELI=OFF -DLUA_MIXER=OFF"
  "tpros        -DPCB=X7  -DPCBREV=TPROS     -DHELI=OFF -DLUA_MIXER=OFF"
  "tprov2       -DPCB=X7  -DPCBREV=TPROV2    -DHELI=OFF -DLUA_MIXER=OFF"
  "t15          -DPCB=X10 -DPCBREV=T15       -DINTERNAL_MODULE_CRSF=ON"
  "t16          -DPCB=X10 -DPCBREV=T16       -DINTERNAL_MODULE_MULTI=ON"
  "t18          -DPCB=X10 -DPCBREV=T18"
  "t15pro       -DPCB=T15PRO"
)

PASS=()
FAIL=()
SKIP=()

# STM32H7 + external-QSPI boards. Their EdgeTX target sets
# FIRMWARE_FORMAT_UF2=YES, so the build emits firmware.uf2 (written by the
# radio's EDGETX_UF2 mass-storage bootloader). A plain firmware.bin from
# these targets is NOT flashable (it's a QSPI image; generic DFU to
# 0x08000000 bricks the radio). For these we ship the .uf2.
QSPI_BOARDS=" tx16smk3 tx15 t15pro "
is_qspi() { [[ "$QSPI_BOARDS" == *" $1 "* ]]; }

for entry in "${TARGETS[@]}"; do
  read -r name extra_opts <<< "$(echo "$entry" | awk '{name=$1; $1=""; print name, $0}')"
  build_dir="$EDGETX/build-${name}-${LANG}"
  log="$LOGS/${name}-${LANG}.log"

  if is_qspi "$name"; then ext="uf2"; else ext="bin"; fi
  out_bin="$OUT/${name}-${LANG}.${ext}"

  # Optional staging path — when BSW_EDGETX_DIR points to BeeSwarmer's
  # `EdgeTX/` source directory, copy into `<dir>/<lang>/<board>.<ext>` so a
  # rebuilt firmware lands in the source tree without an extra step.
  staged_bin=""
  if [[ -n "${BSW_EDGETX_DIR:-}" ]]; then
    staged_bin="$BSW_EDGETX_DIR/$LANG/${name}.${ext}"
  fi

  if [[ -f "$out_bin" ]]; then
    echo "[build_all]  SKIP $name ($LANG, already built)"
    SKIP+=("$name")
    if [[ -n "$staged_bin" && ! -f "$staged_bin" ]]; then
      mkdir -p "$(dirname "$staged_bin")" && cp "$out_bin" "$staged_bin"
    fi
    continue
  fi

  echo
  echo "================================================================"
  echo "[build_all] >>> $name ($LANG)"
  echo "  options: $extra_opts"
  echo "  build:   $build_dir"
  echo "================================================================"

  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  pushd "$build_dir" > /dev/null

  VIRTUAL_ENV="$VENV" PATH="$VENV/bin:$TOOLCHAIN:$PATH" \
    cmake \
      $extra_opts \
      -DUSB_CHANNELS=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DARM_TOOLCHAIN_DIR="$TOOLCHAIN" \
      -DUSE_UNSUPPORTED_TOOLCHAIN=ON \
      -DTRANSLATIONS=$TR \
      "$EDGETX" > "$log" 2>&1
  cfg_rc=$?

  if [[ $cfg_rc -ne 0 ]]; then
    echo "[build_all]  CONFIGURE FAILED for $name (rc=$cfg_rc) — see $log"
    FAIL+=("$name(configure)")
    popd > /dev/null
    continue
  fi

  VIRTUAL_ENV="$VENV" PATH="$VENV/bin:$TOOLCHAIN:$PATH" \
    make -j"$(nproc)" firmware >> "$log" 2>&1
  build_rc=$?

  if [[ $build_rc -ne 0 ]]; then
    echo "[build_all]  BUILD FAILED for $name (rc=$build_rc) — see $log"
    FAIL+=("$name(build)")
    popd > /dev/null
    continue
  fi

  if is_qspi "$name"; then
    bin="$build_dir/arm-none-eabi/firmware.uf2"
  else
    bin="$build_dir/arm-none-eabi/firmware.bin"
  fi
  if [[ ! -f "$bin" ]]; then
    echo "[build_all]  ARTEFACT MISSING for $name ($bin) — see $log"
    FAIL+=("$name(artefact)")
    popd > /dev/null
    continue
  fi

  cp "$bin" "$out_bin"
  size=$(stat -c '%s' "$out_bin")
  echo "[build_all]  OK $name ($LANG)  size=$size  -> $out_bin"
  PASS+=("$name")

  # Mirror into BeeSwarmer/EdgeTX/<lang>/ when BSW_EDGETX_DIR is set.
  if [[ -n "$staged_bin" ]]; then
    mkdir -p "$(dirname "$staged_bin")" && cp "$out_bin" "$staged_bin"
  fi

  popd > /dev/null
done

echo
echo "================================================================"
echo "[build_all] DONE ($LANG): ${#PASS[@]} passed, ${#FAIL[@]} failed, ${#SKIP[@]} skipped"
echo "[build_all] PASS: ${PASS[*]}"
echo "[build_all] FAIL: ${FAIL[*]}"
echo "[build_all] SKIP: ${SKIP[*]}"
echo "================================================================"
ls -la "$OUT"/*-${LANG}.bin 2>/dev/null
