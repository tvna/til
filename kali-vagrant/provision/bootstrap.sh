#!/usr/bin/env bash
# Kali ゲストの初期設定（vagrant up 初回 / vagrant provision で実行）
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

: "${KALI_UPGRADE:=false}"
: "${KALI_PACKAGES:=}"
: "${KALI_TIMEZONE:=Asia/Tokyo}"
: "${KALI_KEYMAP:=jp}"

echo "[bootstrap] timezone=${KALI_TIMEZONE} keymap=${KALI_KEYMAP}"
timedatectl set-timezone "${KALI_TIMEZONE}"
localectl set-keymap "${KALI_KEYMAP}" || true
localectl set-x11-keymap "${KALI_KEYMAP}" || true

apt-get update

if [[ "${KALI_UPGRADE}" == "true" ]]; then
  echo "[bootstrap] full-upgrade"
  apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade
fi

if [[ -n "${KALI_PACKAGES}" ]]; then
  echo "[bootstrap] install: ${KALI_PACKAGES}"
  # shellcheck disable=SC2086
  apt-get -y install ${KALI_PACKAGES}
fi

apt-get -y autoremove
echo "[bootstrap] done"
