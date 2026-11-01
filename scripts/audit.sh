#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт службы SSH изменен на 2222" "2222" "$(sudo sshd -T | awk '/^port/{print $2}')"
check "Ограничение MaxAuthTries равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика по умолчанию для входящего трафика равна deny" "deny" "$(sudo ufw status verbose | awk '/Default:/{print $2}' | tr -d '(),')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n", $1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx синтаксически корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
CHECK_EXPIRY_SECONDS="${CHECK_EXPIRY_SECONDS:-2592000}"
check "Сертификат истекает не ранее чем через 30 дней" "0" "$(openssl x509 -checkend "$CHECK_EXPIRY_SECONDS" -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; echo $?)"

sec_actual="ok"
if [[ -n "$(find /var/www/devops-site -perm -o+w)" ]] || [[ "$(sudo stat -c '%a' /etc/ssl/private/devops.key)" != "600" ]]; then
    sec_actual="fail"
fi
check "В каталоге ресурса нет файлов o+w и права ключа 600" "ok" "$sec_actual"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
