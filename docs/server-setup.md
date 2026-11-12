# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- **Тип и версия ОС:** Ubuntu Server 24.04 LTS (64-bit)
- **Имя узла (hostname):** devops-vm (`devops-vm.devops.local`)
- **Объём оперативной памяти:** 2048 МБ
- **Количество ядер процессора:** 2 vCPU
- **Объём дискового накопителя:** 25 ГБ (динамически расширяемый)
- **Гипервизор:** Oracle VirtualBox 7.x

## 2. Сетевые интерфейсы
- **Адаптер 1 (NAT):**
  - Имя интерфейса: `enp0s3`
  - Полученный IP-адрес: `10.0.2.15/24` (DHCP)
  - Назначение: выход в глобальную сеть Интернет, загрузка пакетов и обновлений
- **Адаптер 2 (Host-only):**
  - Имя интерфейса: `enp0s8`
  - Полученный IP-адрес: `192.168.56.104/24` (DHCP)
  - Назначение: изолированное прямое взаимодействие между хостовой ОС и гостевой ОС
- **Локальный резолвер DNS:** `systemd-resolved` (адрес `127.0.0.53:53`, локальное сопоставление в `/etc/hosts`: `127.0.1.1 devops-vm.devops.local devops-vm`)

## 3. Правило проброса портов
Настроены в свойствах адаптера NAT (Адаптер 1):
- **SSH:** порт хоста `2222` (IP `127.0.0.1`), порт гостя `2222`, протокол TCP
- **HTTP:** порт хоста `80` (IP `127.0.0.1`), порт гостя `80`, протокол TCP
- **HTTPS:** порт хоста `443` (IP `127.0.0.1`), порт гостя `443`, протокол TCP

## 4. Учётные записи
- **student:**
  - UID: 1000
  - Группы: `student`, `adm`, `cdrom`, `sudo`, `dip`, `plugdev`, `lxd`
  - Способ аутентификации: пароль (первичная административная учетная запись)
- **devops:**
  - UID: 1001
  - Группы: `devops`, `sudo`
  - Способ аутентификации: исключительно по открытому ключу (SSH ed25519) без пароля

## 5. Служба SSH
- **Порт службы:** `2222` (прослушивание `0.0.0.0:2222` и `[::]:2222`)
- **Расположение файла конфигурации:** `/etc/ssh/sshd_config.d/99-hardening.conf`
- **Изменённые директивы:**
  - `Port 2222`
  - `PermitRootLogin no`
  - `PasswordAuthentication no`
  - `PubkeyAuthentication yes`
  - `PermitEmptyPasswords no`
  - `MaxAuthTries 3`
  - `LoginGraceTime 30`
  - `AllowUsers devops`
  - `X11Forwarding no`
  - `ClientAliveInterval 300`
  - `ClientAliveCountMax 2`
- **Особенности службы:** отключен сокет-активатор `ssh.socket` (`systemctl disable --now ssh.socket`), служба переведена на постоянный сервис `ssh.service` (`systemctl enable --now ssh.service`).

## 6. Правила межсетевого экрана (UFW)
- **Состояние:** Active
- **Политики по умолчанию:**
  - `default deny incoming` (все входящие соединения запрещены)
  - `default allow outgoing` (все исходящие соединения разрешены)
- **Перечень разрешающих правил:**
  - `2222/tcp LIMIT IN Anywhere` (SSH rate-limited: защита от брутфорса, ограничение не более 6 подключений за 30 секунд)
  - `80/tcp ALLOW IN Anywhere` (HTTP)
  - `443/tcp ALLOW IN Anywhere` (HTTPS)
  - Аналогичные правила для IPv6 (`v6`).
- **Уровень журналирования:** `logging on (medium)` (события UFW BLOCK пишутся в `/var/log/ufw.log`).

## 7. Снимки состояния (снапшоты VirtualBox)
1. `01-clean-install` — чистая установка ОС Ubuntu Server 24.04 LTS до внесения изменений.
2. `02-keys-configured` — создана учетная запись devops, скопирован публичный SSH-ключ, проверен вход без пароля.
3. `03-ssh-hardened` — применено усиление защиты SSH (порт 2222, отключение паролей и root), настроен межсетевой экран UFW.
4. `04-nginx-https` — установлен веб-сервер Nginx, выпущен самоподписанный TLS-сертификат, настроен HTTPS и перенаправление с HTTP.
5. `05-docker-compose` — развёрнута контейнеризированная среда Docker и Docker Compose с приложением devops-app и СУБД PostgreSQL.

## 8. Веб-сервер
- **Устанавливаемый пакет:** `nginx` (версия 1.28.3 из стандартного репозитория Ubuntu).
- **Путь к конфигурации ресурса:** `/etc/nginx/sites-available/devops-site` (активирован через символическую ссылку в `/etc/nginx/sites-enabled/devops-site`; стандартный ресурс `/etc/nginx/sites-enabled/default` удалён).
- **Каталог ресурса, его владелец и права:**
  - Каталог: `/var/www/devops-site`
  - Владелец и группа: `devops:devops`
  - Права на каталог: `755` (`drwxr-xr-x`)
  - Права на публикуемые файлы: `644` (`-rw-r--r--`)
  - Модель доступа: «владелец devops пишет, процесс веб-сервера www-data только читает». Запись для www-data запрещена.
- **Пути к сертификату и ключу, их права:**
  - Сертификат: `/etc/ssl/certs/devops.crt` (владелец `root:root`, права `644`)
  - Закрытый ключ: `/etc/ssl/private/devops.key` (владелец `root:root`, права `600`)
- **Команда формирования сертификата:**
  ```bash
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
  ```
- **Срок действия сертификата:** 365 дней.
- **Параметры TLS и виртуального хоста:**
  - Протоколы: `TLSv1.2 TLSv1.3`
  - Перенаправление HTTP -> HTTPS: код `301 Moved Permanently` через директиву `return 301 https://$host$request_uri;`
  - Пользовательская страница ошибки: `error_page 404 /404.html;`
  - Журналы: `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`.

## 9. Контейнеризация
- **Способ установки Docker Engine и его версия:** установка выполнена из официального репозитория Docker (`https://download.docker.com/linux/ubuntu`) с подключением официального GPG-ключа `/etc/apt/keyrings/docker.asc` (версия Docker Engine: `29.9.3`, плагин Compose: `v5.7.1`). Пакет `docker.io` из репозиториев дистрибутива не использовался.
- **Участники группы docker:** пользователь `devops` включён в группу `docker` (`sudo usermod -aG docker devops`), что позволяет запускать контейнеры и управлять Docker Compose без повышения привилегий через `sudo`.
- **Расположение проекта на сервере:** `/home/devops/app` (`~/app`).
- **Расположение файла .env и его права:** `/home/devops/app/.env`, права доступа `600` (`-rw-------`, владелец `devops:devops`), содержит конфигурационные секреты приложения и базы данных, включая сгенерированный случайный пароль СУБД (`POSTGRES_PASSWORD`). Файл исключён из системы контроля версий Git с помощью `.gitignore` и из контекста сборки Docker через `.dockerignore`. Для шаблонизации подготовлен файл `app/.env.example`.
- **Публикуемые порты и адреса:**
  - Приложение `app` (Flask + Gunicorn): опубликован исключительно на адресе `127.0.0.1:5000:5000` (привязка строго к loopback-интерфейсу хоста исключает прямой сетевой доступ извне в обход правил межсетевого экрана UFW).
  - СУБД `db` (PostgreSQL 16 Alpine): порт `5432` во внешнюю сеть и на хост не публикуется; взаимодействие осуществляется строго внутри изолированной пользовательской bridge-сети Compose `app_backend` по DNS-имени `db`.
- **Именованные тома:** именованный том `app_db_data` (в `docker-compose.yml`: `db_data`), смонтированный в каталог контейнера `/var/lib/postgresql/data` для обеспечения персистентности данных СУБД при перезапусках и пересоздании контейнеров (`docker compose down`).
- **Конфигурация обратного прокси-сервера:** в конфигурации виртуального хоста Nginx `/etc/nginx/sites-available/devops-site` в блоке `server` (порт 443 SSL) настроено проксирование пути `/app/` на локальный порт контейнера:
  ```nginx
  location /app/ {
      proxy_pass http://127.0.0.1:5000/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```
  Завершающий слэш в URL директивы `proxy_pass http://127.0.0.1:5000/;` заменяет префикс `/app/` на `/`, передавая запросы вида `/app/health` приложению как `/health`. При остановленном контейнере Nginx возвращает код `502 Bad Gateway`, фиксируя ошибку подключения `connect() failed (111: Connection refused)` в журнале `/var/log/nginx/devops-site.error.log`.

