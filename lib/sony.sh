#!/usr/bin/env bash
# sony.sh: the fetch half of the Sony source. Sourced by bin/ps5-firmware.
#
# Sony publishes one small XML file per region. This file asks for them and reads
# the facts out of each answer; what the facts mean is decided in lib/sony.jq,
# which runs without a network. Everything it needs from the caller (the timeout,
# the size cap, the temporary directory, the timestamp) is already set by the
# time it is sourced, so the same code can be pointed at a stand-in server.
#
# The host is Sony's own, and its TLS certificate is issued by Sony's own root
# rather than by a public authority, so the root travels with the plugin and is
# handed to curl as the trust anchor. That keeps the read encrypted and
# authenticated: nothing on the way can change a word of it without Sony's key.

SONY_CA="$PLUGIN_DIR/assets/scei-dnas-root-05.pem"
SONY_TITLE_ID=$(jq -r '.titleId' "$LIB_DIR/regions.json")
SONY_VERSION=$(jq -r '.version' "$PLUGIN_DIR/manifest.json")
SONY_AGENT="ps5-firmware-omarchy/$SONY_VERSION (+https://github.com/DanielErikssonCoder/omarchy-ps5-firmware)"
# The suite points this at a stand-in server; a normal run never sets it.
SONY_BASE=${PS5_SONY_BASE:-}

# The address a person (and the panel) can read as the source of a reading.
sony_source_url() {
  if [[ -n $SONY_BASE ]]; then
    printf '%s' "$SONY_BASE/list/<region>/updatelist.xml"
  else
    printf 'https://f<region>01.ps5.update.playstation.net/update/ps5/official/%s/list/<region>/updatelist.xml' \
      "$SONY_TITLE_ID"
  fi
}

# sony_url <code> -> the list URL for one region.
sony_url() {
  local code=$1
  if [[ -n $SONY_BASE ]]; then
    printf '%s/list/%s/updatelist.xml' "$SONY_BASE" "$code"
  else
    printf 'https://f%s01.ps5.update.playstation.net/update/ps5/official/%s/list/%s/updatelist.xml' \
      "$code" "$SONY_TITLE_ID" "$code"
  fi
}

# Why one region did not answer, in our own words rather than curl's. The reader
# sees this in the panel, so it says what happened and not which tool noticed.
sony_reason() {
  local status=$1 errfile=$2 size=$3 first code
  first=$(head -1 "$errfile" 2>/dev/null || true)
  if ((size > SOURCE_MAX_BYTES)); then
    printf 'the reply is larger than %s bytes' "$SOURCE_MAX_BYTES"
    return 0
  fi
  case $status in
  0) printf 'the reply was empty' ;;
  6) printf 'the host did not resolve' ;;
  7) printf 'the host refused the connection' ;;
  22)
    code=$(printf '%s' "$first" | sed -n 's/.*error: \([0-9][0-9][0-9]\).*/\1/p' | head -1)
    if [[ -n $code ]]; then printf 'HTTP %s' "$code"; else printf 'the server answered with an error'; fi
    ;;
  28) printf 'the reply did not finish in %s seconds' "$SOURCE_TIMEOUT" ;;
  35) printf 'the connection failed during the handshake' ;;
  47) printf 'the reply was a redirect, which is refused' ;;
  60) printf 'the certificate did not verify against the Sony root the plugin carries' ;;
  63) printf 'the reply is larger than %s bytes' "$SOURCE_MAX_BYTES" ;;
  *) printf 'the request failed (curl exit %s)' "$status" ;;
  esac
}

# One facts object for a region that could not be read.
sony_unreadable() {
  local code=$1 url=$2 reason=$3
  jq -cn --arg code "$code" --arg url "$url" --arg reason "$reason" \
    '{code: $code, ok: false, url: $url, error: $reason}'
}

# sony_region <code> -> one facts object on stdout. Never fails: a region that
# cannot be read is part of the answer, not the end of the run.
sony_region() {
  local code=$1 url xml status size out
  url=$(sony_url "$code")
  xml="$TMP_DIR/sony-$code.xml"

  # The same guardrails as any other source in this plugin: one host, no
  # redirects, a size cap on bytes written rather than on time, and a connection
  # that trickles gets dropped. TLS is required and measured against the root
  # that travels with the plugin, but only for the real host: the stand-in in the
  # test suite is a plain local server.
  local -a tls=()
  if [[ $url == https://* ]]; then
    tls=(--proto '=https' --cacert "$SONY_CA")
  fi

  curl --silent --show-error --location --max-redirs 0 "${tls[@]}" \
    --user-agent "$SONY_AGENT" --max-time "$SOURCE_TIMEOUT" \
    --max-filesize "$SOURCE_MAX_BYTES" --speed-limit 1024 --speed-time 30 \
    --fail "$url" 2>"$xml.err" \
    | head -c "$((SOURCE_MAX_BYTES + 1))" >"$xml"
  status=${PIPESTATUS[0]}

  size=$(wc -c <"$xml" 2>/dev/null || echo 0)
  if ((size == 0)) || ((size > SOURCE_MAX_BYTES)); then
    sony_unreadable "$code" "$url" "$(sony_reason "$status" "$xml.err" "$size")"
    return 0
  fi

  # One call, one line per fact, separated by a character that cannot appear in
  # any of them. libxml2 does not turn "\n" into a newline, so the separator is a
  # pipe and the split happens on this side.
  out=$(xmllint --xpath 'concat(
      string(//region/@id), "|",
      string(//force_update/system/@upd_version), "|",
      string(//force_update/system/@sdk_version), "|",
      string(//system_pup/@upd_version), "|",
      string(//system_pup/@sdk_version), "|",
      string(//system_pup/@label), "|",
      string(//system_pup/update_data/@update_type), "|",
      string(//system_pup/update_data/image/@size), "|",
      string(//system_pup/update_data/image), "|",
      count(//force_update/system/conditional_requirement))' "$xml" 2>"$xml.parse.err") || true

  local -a f=()
  IFS='|' read -r -a f <<<"$out"

  # A file that is not a list for the region we asked for is not a reading: the
  # region id has to match, and every fact has to be there.
  if ((${#f[@]} < 10)) || [[ ${f[0]} != "$code" ]] || [[ -z ${f[3]} ]]; then
    sony_unreadable "$code" "$url" "the reply was not a PlayStation 5 list for $code"
    return 0
  fi

  jq -cn --arg code "$code" --arg url "$url" --arg min "${f[1]}" --arg minsdk "${f[2]}" \
    --arg latest "${f[3]}" --arg latsdk "${f[4]}" --arg label "${f[5]}" \
    --arg utype "${f[6]}" --arg size "${f[7]}" --arg pup "${f[8]}" --arg cond "${f[9]}" \
    '{code: $code, ok: true, url: $url,
      minimumRaw: $min, minimumSdk: $minsdk,
      latestRaw: $latest, latestSdk: $latsdk,
      label: $label, updateType: $utype,
      size: $size, pupUrl: $pup, conditions: $cond}'
}

# sony_manifest -> writes the manifest every other part of the plugin already
# knows, or returns 1 with the reason in $TMP_DIR/curl.err when no region
# answered at all. All of them failing is the source being down, which is its own
# answer and has its own notification.
sony_manifest() {
  local code obj answered=0 facts="$TMP_DIR/sony-facts.jsonl"
  : >"$facts"

  while read -r code; do
    obj=$(sony_region "$code")
    [[ $(jq -r '.ok' <<<"$obj") == "true" ]] && answered=$((answered + 1))
    printf '%s\n' "$obj" >>"$facts"
  done < <(jq -r '.regions[].code' "$LIB_DIR/regions.json")

  if ((answered == 0)); then
    printf 'none of the %s regional lists answered (first reason: %s)\n' \
      "$(jq -r '.regions | length' "$LIB_DIR/regions.json")" \
      "$(jq -rs '[.[] | select(.ok == false) | .error][0] // "no answer"' "$facts")" \
      >"$TMP_DIR/curl.err"
    return 1
  fi

  jq --slurp --slurpfile regions "$LIB_DIR/regions.json" \
    --arg checkedAt "$NOW" --arg sourceUrl "$(sony_source_url)" \
    -f "$LIB_DIR/sony.jq" "$facts" >"$TMP_DIR/manifest.json"
}
