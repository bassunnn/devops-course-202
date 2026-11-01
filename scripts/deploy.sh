#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops" # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# Переход в корень репозитория для работы из любого каталога (Требование 2)
cd "$(git rev-parse --show-toplevel)"

# 1. Разбор аргумента --dry-run
DRY_RUN=""
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        DRY_RUN="--dry-run"
    else
        echo "Ошибка: неизвестный аргумент '$1'" >&2
        exit 1
    fi
fi

# 2. Проверки по требованиям 4 и 5
# Требование 4: если файл site/index.html отсутствует
if [[ ! -f "site/index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует" >&2
    exit 1
fi

# Требование 5: если в репозитории есть незафиксированные изменения (в рабочей копии или в индексе)
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Ошибка: в репозитории присутствуют незафиксированные изменения" >&2
    exit 1
fi

# 3. Синхронизация каталога site/ на ${REMOTE}:${REMOTE_DIR}
RSYNC_ARGS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ -n "$DRY_RUN" ]]; then
    RSYNC_ARGS+=("$DRY_RUN")
fi

rsync "${RSYNC_ARGS[@]}" "site/" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ -n "$DRY_RUN" ]]; then
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} и завершение с корректным кодом возврата
if ! curl -f -s -o /dev/null --cacert "${CA_CERT}" "${SITE_URL}"; then
    echo "Ошибка: проверка доступности ${SITE_URL} не пройдена" >&2
    exit 1
fi

# Требование 7: вывод короткого хеша доставленного коммита
git rev-parse --short HEAD
exit 0
