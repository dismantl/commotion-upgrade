#!/bin/sh

. /lib/functions.sh

SCRIPTS_TAR=/tmp/commotion-upgrade-scripts
SCRIPTS_DIR=/tmp/commotion-upgrade
ERR_PARSE=3
ERR_RUN=4

print_usage() {
  cat << EOF
Commotion Upgrade Utility
https://commotionwireless.net

Usage: commotion-upgrade [-i|--interactive] <image file>
EOF
}

die() { # <exit code>
  [ -d "$SCRIPTS_DIR" ] && rm -rf "$SCRIPTS_DIR"
  [ -f "$SCRIPTS_TAR" ] && rm -f "$SCRIPTS_TAR"
  exit $1
}

get_magic_long() {
  (tail -c-4 "$1" | hexdump -n 4 -e '1/4 "%04x"') 2>/dev/null
}

get_scripts_len() {
  (tail -c-8 "$1" | hexdump -n 4 -e '1/4 "%d"') 2>/dev/null
}

check_commotion_image() { # image
  local image="$1"
  local magic=$(get_magic_long "$image")
  case "$magic" in
    c0febabe) return 0;;
    *) return 1;;
  esac
}

# parse options
[ $# -eq 0 -o $# -gt 2 ] && {
  print_usage
  exit 1
}
while [ -n "$1" ]; do
  case "$1" in
    -i|--interactive) interactive=1;;
    *) IMAGE="$1";;
  esac
  shift;
done

([ -f "$IMAGE" ] && check_commotion_image "$IMAGE") || {
  echo "Invalid image file"
  print_usage
  exit 1
}

# read length of scripts tarball
scripts_len=$(get_scripts_len "$IMAGE")

# extract scripts from image
tail -c-$((scripts_len + 8)) "$IMAGE" |dd bs=$scripts_len count=1 2>/dev/null > "$SCRIPTS_TAR"
mkdir -p "$SCRIPTS_DIR"
cd "$SCRIPTS_DIR"
tar zxvf "$SCRIPTS_TAR" &>/dev/null

[ -f "$SCRIPTS_DIR/manifest" ] || {
  echo "Image is missing manifest"
  die 1
}

# verify signature of manifest (if not signed w/ Commotion pub key, give warning to user)
if [ -f "$SCRIPTS_DIR/manifest.asc" ]; then
  config_load serval
  config_get signing_key settings signing_key
  commotion serval-crypto verify $signing_key "$(cat "$SCRIPTS_DIR/manifest.asc")" "$(cat "$SCRIPTS_DIR/manifest")" |grep true
  if [ $? -eq 1 -a -n $interactive ]; then
    read -p "WARNING: This image was not signed by the Commotion development team's signing key or has an invalid signature. If you did not custom build this image from source, you should abort this upgrade. Continue? [y/N] " cont
    [ "$cont" != "y" ] && exit 0
  else
    echo "WARNING: This image was not signed by the Commotion development team's signing key or has an invalid signature."
  fi
else
  if [ -n $interactive ];
    read -p "WARNING: This image was not cryptographically signed. If you downloaded this image from the Commotion Wireless website, you should abort this upgrade. Continue? [y/N] " cont
    [ "$cont" != "y" ] && exit 0
  else
    echo "WARNING: This image was not cryptographically signed."
  fi
fi

# run scripts
awk -v SCRIPTS_DIR="$SCRIPTS_DIR" \
-v ERR_PARSE=$ERR_PARSE \
-v ERR_RUN=$ERR_RUN \
-v BACKUPS="$SCRIPTS_DIR/changed" \
-v LOG="$SCRIPTS_DIR/log" \
-f /lib/upgrade/commotion/upgrade.awk "$SCRIPTS_DIR/manifest"

[ $? != 0 ] && exit 1

# TODO install image


die 0