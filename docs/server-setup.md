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

## 10. Ansible

### 10.1. Расположение и структура файлов конфигурации
Все плейбуки, инвентари и роли Ansible сосредоточены в каталоге `ansible/`:
- `ansible/ansible.cfg` — конфигурация исполнения (отключение Host Key Checking при строгом контроле, `pipelining = True`, `force_handlers = True` для гарантированного исполнения обработчиков при сбоях, путь к инвентарю по умолчанию `inventory/prod.ini`).
- `ansible/requirements.yml` — зависимости от внешних коллекций (`ansible.posix`, `community.docker`, `community.general`).
- `ansible/inventory/bootstrap.ini` — инвентарь первичного наката от имени пользователя `student` с использованием приватного SSH-ключа `~/.ssh/devops_vm`.
- `ansible/inventory/prod.ini` — штатный инвентарь для управления от имени пользователя `devops` без использования паролей (`sudo NOPASSWD`).
- `ansible/group_vars/all.yml` — централизованные переменные деплоя приложения.
- `ansible/site.yml` — главный управляющий плейбук настройки узла и развёртывания стека сервисов.
- `ansible/verify.yml` — независимый аудит-плейбук только для чтения (read-only verification).

### 10.2. Архитектурная схема ролей
Плейбук разделен на четыре строго демаркированные роли, исполняемые последовательно:

```text
[ Control Node (WSL Ubuntu) ]
              │
              ▼ SSH (Key auth: devops_vm)
┌─────────────────────────────────────────────────────────┐
│                      Managed Node                       │
│  devops-vm (Host-only: 192.168.56.104, NAT: 127.0.0.1)   │
│                                                         │
│  1. Role 'base'                                         │
│     ├── Проверка платформы (Ubuntu >= 24.04 amd64)      │
│     ├── Базовые утилиты (curl, ufw, python3-requests)   │
│     └── Docker CE из официального репозитория (deb822)  │
│                                                         │
│  2. Role 'ssh'                                          │
│     ├── Создание пользователя devops (группы docker/sudo)│
│     ├── Установка SSH-ключа и NOPASSWD в sudoers.d/devops│
│     ├── Харденинг sshd (/etc/ssh/sshd_config.d/)        │
│     │   (PasswordAuth no, PermitRootLogin no)           │
│     └── UFW (default deny in, allow 22, 80/tcp)         │
│                                                         │
│  3. Role 'nginx'                                        │
│     ├── Установка Nginx                                 │
│     ├── Конфигурация Reverse Proxy на 127.0.0.1:5000    │
│     ├── Отключение дефолтного сайта (default)           │
│     └── Handler: nginx -t -> systemctl reload nginx     │
│                                                         │
│  4. Role 'app'                                          │
│     ├── Pull проверенного контейнера по точному SHA     │
│     ├── Запуск devops-ci-app (127.0.0.1:5000:5000)      │
│     └── Health-check (uri http://127.0.0.1:5000/health) │
└─────────────────────────────────────────────────────────┘
```

### 10.3. Перечень переменных `group_vars/all.yml`
```yaml
---
app_image: "ghcr.io/bassunnn/devops-ci-app"
app_tag: "e4d55bac97f4b48accbb36a8666e582620d775d8"
app_container_name: "devops-ci-app"
app_host_port: 5000
app_internal_port: 5000
```
- `app_image`: имя опубликованного Docker-образа в реестре GitHub Container Registry (GHCR).
- `app_tag`: полный неизменяемый SHA коммита, на базе которого собран и протестирован образ в CI.
- `app_container_name`: уникальное имя исполняемого контейнера.
- `app_host_port`: порт локального интерфейса хоста (строго `127.0.0.1:5000`), на который проксирует Nginx.
- `app_internal_port`: внутренний порт веб-сервера Gunicorn внутри контейнера (5000).

### 10.4. Команды запуска

#### Первичная настройка (Bootstrap):
Выполняется один раз на чистой виртуальной машине:
```bash
ansible-playbook -i inventory/bootstrap.ini site.yml
```

#### Штатный деплой и управление конфигурацией (Prod):
Все последующие запуски выполняются с дефолтным инвентарём от имени учетной записи `devops`:
```bash
ansible-playbook site.yml
```

#### Независимый аудит состояния (Verify):
```bash
ansible-playbook verify.yml
```

### 10.5. Сценарий восстановления после аварии (Disaster Recovery & Drift Management)
В случае ручного изменения конфигурации узла (дрейф конфигурации) либо аварийной остановки контейнера:
1. Запуск `ansible-playbook verify.yml` обнаруживает сбой и завершается с кодом ошибки, точно указывая на нарушенное условие (например, остановку контейнера или дрейф портов).
2. Запуск `ansible-playbook site.yml` без дополнительных ручных манипуляций приводит состояние управляемого узла в строго декларативное состояние:
   - восстанавливает удаленный или остановленный контейнер;
   - обновляет файл конфигурации виртуального хоста `/etc/nginx/sites-available/devops-ci-app`;
   - валидирует синтаксис Nginx (`nginx -t`) и мягко перезагружает веб-сервер (`systemctl reload nginx`) через зарегистрированный handler;
   - проверяет эндпоинт `/health` до возвращения HTTP 200 OK.

### 10.6. Результаты проверки идемпотентности
При повторном запуске плейбука `site.yml` на уже сконфигурированной системе не изменяется ни один параметр, а обработчики перезагрузки служб не вызываются:
```text
PLAY RECAP *********************************************************************
devops-vm                  : ok=24   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### 10.7. Журналы прогонов плейбука

#### Итоги первичного наката (Bootstrap):
```text
PLAY RECAP *********************************************************************
devops-vm                  : ok=26   changed=17   unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

#### Итоги повторного наката (Идемпотентный прогон):
```text
PLAY RECAP *********************************************************************
devops-vm                  : ok=24   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

#### Итоги восстановления дрейфа (Incident 1 — Drift Fix):
```text
PLAY RECAP *********************************************************************
devops-vm                  : ok=26   changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

#### Итоги аудита (Verify):
```text
PLAY RECAP *********************************************************************
devops-vm                  : ok=7    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
