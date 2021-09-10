#!/bin/bash

# Exit code indicating "a service is unavailable", from
# /usr/include/sysexits.h. The verify-file function will return this code if
# prerequisites for verification are unavailable.
EX_UNAVAILABLE=69

verify-file() {
  local sig="$1"
  local doc="$2"

  # The GPG binary is required to be present in order to perform file download
  # verification. If it is not present, return EX_UNAVAILABLE.
  if ! command -v gpg >/dev/null; then
    echo "gpg binary not found; required in path for checking download"
    return "$EX_UNAVAILABLE"
  fi

  # The verification key must be present, or it must be possible to download it
  # from the keyserver to perform file verification. If it is not present,
  # return EX_UNAVAILABLE.
  if ! { gpg --list-keys "$PT_key_id" || gpg --keyserver "$PT_key_server" --recv-key "$PT_key_id"; } then
    echo "Unable to download verification key ${PT_key_id}"
    return "$EX_UNAVAILABLE"
  fi

  # Perform the verification and return success or failure.
  if gpg --verify "$sig" "$doc"; then
    echo "Signature verification succeeded"
    return 0
  else
    echo "Signature verification failed"
    return 1
  fi
}

download() {
  printf '%s\n' "Downloading: ${1}"
  curl -s -f -L -o "$2" "$1"
}

download-size-verify() {
  local source="$1"
  local path="$2"

  urisize=$(curl -s -L --head "$source" | sed -rn 's/Content-Length: ([0-9]+)/\1/p' | tr -d '\012\015')
  filesize=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null)

  echo "Filesize: ${filesize}"
  echo "Content-Length header: ${urisize}"

  # Assume that if the file exists and is the same size, we don't have to
  # re-download.
  if [[ ! -z "$urisize" && ! -z "$filesize" && "$filesize" -eq "$urisize" ]]; then
    echo "File size matches HTTP Content-Length header. Using file as-is."
    exit 0
  else
    download "$source" "$path"
  fi
}

download-signature-verify() {
  local source="$1"
  local path="$2"

  if ! download "${source}.asc" "${path}.asc" ; then
    echo "Unable to download ${source}.asc. Skipping verification."
    download-size-verify "$source" "$path"
    return "$?"
  fi

  echo "Verifying ${path}..."
  verify_output=$(verify-file "${path}.asc" "$path");
  verify_exit="$?"
  if [[ "$verify_exit" -eq "$EX_UNAVAILABLE" ]]; then
    echo "Verification unavailable. ${verify_output}. Skipping verification."
    download-size-verify "$source" "$path"
  elif [[ "$verify_exit" -eq "1" ]]; then
    echo "$verify_output"
    download "$source" "$path"
    echo "Verifying ${path}..."
    verify-file "${path}.asc" "$path"
  fi
}

if [[ "$PT_verify_download" == "true" ]]; then
  download-signature-verify "$PT_source" "$PT_path"
else
  download-size-verify "$PT_source" "$PT_path"
fi
