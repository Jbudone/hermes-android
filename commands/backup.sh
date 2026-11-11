#!/usr/bin/env bash
# backup.sh — export the phone's SMS, MMS (text + media) and call log over adb.
#
# No root required. MMS attachments live in the telephony provider's private
# storage, so they are pulled part-by-part via content://mms/part (AirDroid and
# other file-transfer apps cannot reach them).
#
#   hermes-android backup                 # -> ~/phone-backups/<date>/
#   hermes-android backup --dir OUT       # custom destination
#   hermes-android backup --no-media      # text/metadata only (fast)
#
# RESULT: sms.txt, mms_meta.txt, mms_parts_text.txt, calls.txt, and mms_media/
# (one file per image/video/audio/pdf part). This is an EXPORT, not a flashable
# image: re-import with a tool like "SMS Backup & Restore" (convert first), or
# read the .txt directly. Verify a clear with a fresh query afterwards — an
# immediate read can be served by the pre-clear provider process.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/android-ops.sh
. "$HERE/../lib/android-ops.sh"

OUT="${HOME}/phone-backups/$(date +%Y-%m-%d)"; MEDIA=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)      OUT="$2"; shift ;;
    --no-media) MEDIA=0 ;;
    -h|--help)  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ao_die "unknown arg: $1 (try: backup [--dir OUT] [--no-media])" ;;
  esac; shift
done

T="$(ao_target)" || ao_die "no adb target (see docs/PAIRING.md)"
mkdir -p "$OUT" "$OUT/mms_media" || ao_die "cannot create $OUT"

rows() { if [ -f "$1" ]; then c="$(grep -c 'Row:' "$1" 2>/dev/null)"; echo "${c:-0}"; else echo 0; fi; }

ao_info "exporting SMS / MMS / call log -> $OUT"
_ao_adb_raw -s "$T" shell 'content query --uri content://sms'                            >"$OUT/sms.txt"           2>/dev/null || true
_ao_adb_raw -s "$T" shell 'content query --uri content://mms'                            >"$OUT/mms_meta.txt"      2>/dev/null || true
_ao_adb_raw -s "$T" shell 'content query --uri content://mms/part --projection _id,mid,ct,text' >"$OUT/mms_parts_text.txt" 2>/dev/null || true
_ao_adb_raw -s "$T" shell 'content query --uri content://call_log/calls'                  >"$OUT/calls.txt"         2>/dev/null || true

if [ "$MEDIA" = 1 ]; then
  grep -oE '_id=[0-9]+, mid=[0-9]+, ct=(image|video|audio)/[A-Za-z0-9.+-]+|_id=[0-9]+, mid=[0-9]+, ct=application/pdf' \
    "$OUT/mms_parts_text.txt" >"$OUT/media_list.txt" 2>/dev/null || true
  total="$(wc -l < "$OUT/media_list.txt" 2>/dev/null || echo 0)"
  ao_info "pulling $total MMS media part(s) — a few minutes..."
  i=0; ok=0
  while IFS= read -r line; do
    i=$((i+1)); id="${line#_id=}"; id="${id%%,*}"; ct="${line##*ct=}"
    case "$ct" in
      image/jpeg) e=jpg ;;  image/heic) e=heic ;; image/png) e=png ;; image/gif) e=gif ;;
      video/mp4) e=mp4 ;;   video/3gpp) e=3gp ;;  audio/mp4) e=m4a ;; audio/x-m4a) e=m4a ;;
      application/pdf) e=pdf ;; *) continue ;;
    esac
    f="$OUT/mms_media/$id.$e"
    if _ao_adb_raw -s "$T" exec-out content read --uri "content://mms/part/$id" >"$f" 2>/dev/null \
       && [ "$(wc -c <"$f" 2>/dev/null || echo 0)" -gt 200 ]; then
      ok=$((ok+1))
    else
      rm -f "$f"
    fi
    [ $((i % 200)) -eq 0 ] && ao_info "  $i/$total (saved $ok)"
  done <"$OUT/media_list.txt"
  ao_ok "media: $ok file(s), $(du -sh "$OUT/mms_media" 2>/dev/null | cut -f1)"
fi

ao_ok "SMS=$(rows "$OUT/sms.txt")  MMS=$(rows "$OUT/mms_meta.txt")  MMS parts=$(rows "$OUT/mms_parts_text.txt")  calls=$(rows "$OUT/calls.txt")"
ao_info "export complete: $OUT  (restore: re-import with SMS Backup & Restore, or read the .txt)"
