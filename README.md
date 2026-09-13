# auto-xray

`auto-xray` — серверный TUI и CLI для установки Xray из Remnawave-подписки формата `XRAY_JSON`. Он показывает доступные профили, запускает выбранный полный JSON-конфиг, регулярно обновляет подписку и переключается только на профиль, который проходит синтаксическую и реальную HTTPS-проверку через Xray.

Поддерживаются Debian 11–13, Ubuntu 20.04/22.04/24.04/26.04 и Arch Linux на `x86_64` и `aarch64`. Xray можно запускать непосредственно на хосте или в уже установленном Docker Engine.

## Быстрый старт

Скачайте скрипт и checksum из последнего [GitHub Release](https://github.com/GigantPro/auto-xray/releases):

```bash
curl -fLO https://github.com/GigantPro/auto-xray/releases/latest/download/auto-xray
curl -fLO https://github.com/GigantPro/auto-xray/releases/latest/download/auto-xray.sha256
sha256sum -c auto-xray.sha256
chmod +x auto-xray
sudo ./auto-xray
```

Мастер предложит:

1. Host или Docker. По умолчанию используется host.
2. Xray 26.7.28, последний опубликованный релиз, включая prerelease, либо найденный системный Xray.
3. URL Remnawave-подписки.
4. Профиль из массива `XRAY_JSON` — выбор выполняется стрелками.
5. Интервал из `profile-update-interval`, 1 час или 12 часов.
6. Автозапуск и backend управления: systemd или cron.

Скрипт сначала показывает отсутствующие зависимости. Они устанавливаются только после подтверждения. Docker никогда не устанавливается автоматически.

## Автоматическая установка

URL лучше передавать через root-readable файл, чтобы токен не оказался в shell history или списке процессов:

```bash
sudo install -m 600 /dev/null /root/auto-xray-subscription
sudoedit /root/auto-xray-subscription

sudo ./auto-xray install \
  --non-interactive \
  --deployment host \
  --xray-version recommended \
  --subscription-url-file /root/auto-xray-subscription \
  --profile 1 \
  --interval subscription \
  --autostart true \
  --scheduler systemd \
  --install-deps \
  --yes
```

Без `--install-deps` non-interactive установка завершится, если не хватает `curl`, `jq`, `unzip`, CA certificates, `flock` или выбранного scheduler. Для Docker-режима Engine должен быть установлен и запущен заранее.

`--xray-version latest` разрешается в конкретную версию один раз. Обновление подписки не обновляет Xray core. Для явного обновления выполните:

```bash
sudo auto-xray core-upgrade --xray-version latest
```

## Управление

```bash
sudo auto-xray status
sudo auto-xray update
sudo auto-xray logs
sudo auto-xray logs --follow
sudo auto-xray start
sudo auto-xray stop
sudo auto-xray restart
sudo auto-xray configure
sudo auto-xray uninstall
```

`configure` меняет настройки внутри текущего host/Docker режима. Для смены режима сначала выполните `uninstall`, затем новую установку.

## Обновление и failover

Preferred-профиль определяется его `remarks` и порядковым номером среди одинаковых названий. При обновлении он проверяется первым. Если профиль исчез или не работает, auto-xray перебирает массив с начала. Временный fallback не меняет preferred-профиль, поэтому при следующем обновлении исходный вариант будет проверен снова.

Для каждого кандидата выполняются:

- `xray run -test` выбранной версией core;
- запуск полного конфига без изменения его `routing` и `outbounds`;
- HTTPS-запрос через первый локальный SOCKS или HTTP inbound.

Проверка требует локальный SOCKS/HTTP inbound и на время обновления создаёт короткий перерыв в работе. Если все кандидаты неуспешны, предыдущий last-known-good конфиг восстанавливается вместе с прежним состоянием процесса. Параллельные обновления блокируются `flock`.

## Файлы и безопасность

- `/etc/auto-xray` — URL, HWID и настройки; каталог `0700`, секретные файлы `0600`.
- `/var/lib/auto-xray` — active/last-known-good конфиги и состояние.
- `/var/log/auto-xray` — журналы host/cron backend.
- `/opt/auto-xray` — загруженные Xray binaries.
- `/usr/local/bin/auto-xray` — установленный launcher.

URL подписки и содержимое JSON не печатаются в журналы. Загрузки Xray проверяются по `SHA2-256` из официального `.dgst`. При выборе `installed` используется найденный бинарник напрямую, но его существующий service и конфиг не изменяются. Конфликт занятых inbound-портов приведёт к отклонению кандидата, а не к остановке чужого процесса.

## Разработка и релизы

```bash
make build VERSION=0.1.0
make test
```

Исходники хранятся модульно в `src/`, а сборка создаёт один `dist/auto-xray`. Push тега вида `v0.1.0` запускает тесты, строит версионированный скрипт и публикует его вместе с SHA-256 в GitHub Releases.

Проект распространяется по лицензии GPL-3.0.
