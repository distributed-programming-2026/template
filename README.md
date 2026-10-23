# Service template

Каркас Go-модулей с HTTP/OpenAPI, gRPC/protobuf и событийным взаимодействием через `go-sdk`.

## Проверка и локальное окружение

Нужны mise, Python 3 и Docker.

```sh
mise trust
mise install
mise run generate-module billing
mise run all
mise run local-up
```

`local-up` находит все `modules/*/compose.yaml`, генерирует контракты и собирает
Linux-бинарники через модульные задачи mise. Затем запускает общую инфраструктуру,
создаёт базы и пользователей из модульных `docker/mysql/init.sql` и поднимает
сервисы. SQL подготовки запускается при каждом старте, чтобы новые модули работали
и с уже существующим volume MySQL.

Корневой `compose.yaml` содержит gateway, MySQL и RabbitMQ. Каждый модуль описывает
свои сервисы, очередь, настройки подключения и подготовку базы у себя.

Gateway использует образ `ghcr.io/distributed-programming-2026/gateway:v0.0.1`
(Linux/amd64; на ARM Docker использует эмуляцию). Общая конфигурация gateway
находится в `config/gateway/`, маршруты и объявления интерцепторов каждого
модуля — в `modules/<name>/config/gateway/`.

Перед `local-up` и `local-config` задача рекурсивно собирает `.yaml`/`.yml` из
этих каталогов в `dist/local/gateway/`. Учитываются модули с `compose.yaml`;
одноимённые файлы разных модулей не конфликтуют, удалённые конфиги убираются.
Этот каталог монтируется в `/config` read-only. YAML не объединяется скриптом:
проверка и merge по `kind`/`weight` выполняются самим gateway. При пересечении
маршрутов задавайте разные `weight`; больший вес имеет приоритет.

`local-up` сначала проверяет конфиги командой `check-config` из образа gateway,
затем запускает окружение. Хеш содержимого передаётся в Compose, поэтому повторный
`local-up` пересоздаёт gateway после изменения конфигов. Hot reload отсутствует.
Не редактируйте `dist/local/gateway/` вручную. Для запуска напрямую через
`docker compose` сначала выполните `mise run local-config`, чтобы собрать конфиги.

Каждый новый модуль получает маршрут `/<name>/api/...` с удалением `/<name>`
перед проксированием на `<name>-service:8082` внутри Compose-сети. Например:

```sh
curl -X POST localhost/billing/api/public/v1/echo \
  -H 'Content-Type: application/json' -d '{"body":"привет"}'
curl -f localhost:15000/readyz
```

Gateway работает и без модулей: неизвестные маршруты возвращают 404.
Порты задаются через `LOCAL_GATEWAY_PORT` (80) и
`LOCAL_GATEWAY_HEALTH_PORT` (15000).

```sh
mise run local-config
mise run local-status
mise run local-logs
mise run local-down
```

`local-config` показывает объединённую конфигурацию без запуска контейнеров.
`local-down` сохраняет volumes с данными. Имя Compose-проекта задаётся через
`LOCAL_ENV_PROJECT` (по умолчанию `distributed-programming-local`).

Для первого созданного модуля по умолчанию доступны gRPC на 8081, HTTP на 8082 и health consumer
на 8083. Остальные модули получают следующие свободные порты по порядку имён;
`local-up` печатает назначенные порты. Назначения можно задать явно через
`<MODULE>_GRPC_PORT`, `<MODULE>_HTTP_PORT`, `<MODULE>_MESSAGE_HANDLER_PORT`.
Инфраструктурные порты переопределяются через `LOCAL_MYSQL_PORT`, `LOCAL_AMQP_PORT`
и `LOCAL_AMQP_MANAGEMENT_PORT`.

```sh
curl -X POST localhost:8082/api/public/v1/echo \
  -H 'Content-Type: application/json' -d '{"body":"привет"}'
```

Ответ содержит `operationID`; consumer пишет `echo received` в JSON-лог.
Подробности контрактов, настроек и гарантий: [README шаблона](mise-tasks/generate-module.d/README.md.tpl).

## Новый модуль и миграции

```sh
mise run generate-module billing
mise run //modules/billing:all
mise run //modules/billing:generate-migration "Create invoices table"
```

Исходник шаблона находится в `mise-tasks/generate-module.d` и не входит в `go.work`
или список модулей mise. Все файлы шаблона имеют суффикс `.tpl`.
Генератор записывает их в `modules/<name>` без этого суффикса, переименовывает module path, импорты,
каталог `internal/template`, protobuf-сервисы, CLI/env-префиксы и модульный Compose.
Затем генерирует Go-код из контрактов и добавляет модуль в `go.work`.
Имя модуля должно соответствовать `[a-z][a-z0-9_]*`; существующий каталог не перезаписывается.

Генерация рекурсивно находит все `.proto` внутри модуля, включая `internal` и
другие директории. Go-файлы создаются рядом с исходными схемами.
Protobuf-дескрипторы используют путь с именем модуля, например
`billing/api/events/events.proto`. Это позволяет импортировать контракты разных
модулей в одном приложении без конфликта регистрации одинаковых имён `.proto`.
В `.proto` import задаётся от общей директории `modules`, например
`import "billing/internal/messages/types.proto";`. Один и тот же файл всегда
должен иметь один канонический путь, включая имя модуля. Для импорта Go-пакетов
между директориями задаётся полный `go_package`, например
`billing/internal/messages;messages`. Импорт контрактов между Go-модулями
оформляется через `require` и локальный `replace` в `go.mod`.

Генератор миграций создаёт `version<timestamp>.go` и регистрирует миграцию в
`factory.go`. Пока `Up` не реализован, миграция возвращает ошибку. Версия всегда
больше существующих, в том числе при генерации нескольких миграций в одну секунду.

Пример gRPC-интерцептора находится в `internal/<name>/infra/handlers/gateway`
каждого нового модуля и подключён к его маршруту. Контракт gateway `v0.0.1`
скопирован в `lib/gateway/interceptor` (изменён только `go_package`);
`mise run //lib:generate` генерирует общий Go-пакет для всех модулей. При обновлении
контракта синхронизируйте `.proto` с gateway. Примеры запросов и решений приведены
в README создаваемого модуля.

Общий exchange `domain-event` описан в `lib/event`. Модули описывают свои очереди
и bindings, сохраняя общий exchange.

## Проверки

```sh
mise run all
mise run //modules/billing:integration-tests
mise run check-generator
mise run check-local-env
```

`all` выполняет генерацию, tidy, Linux-сборку, unit и интеграционные тесты, lint. Интеграционные
тесты находятся в `internal/integration-tests` и исключены из обычной задачи `test`.
Задача mise собирает Linux-бинарник и Docker-образ модуля. `TestMain` поднимает
MySQL, RabbitMQ, сервис и consumer в общей изолированной Docker-сети.
Оба приложения запускаются из собранного образа; API доступны через случайные
порты хоста.

Проверка генераторов работает во временной копии: создаёт `sample_echo` и `sample_other`,
проверяет совместный импорт RPC/event-контрактов двух модулей, генерацию вне `api`,
междиректорный Protobuf import, миграции,
объединение Compose и полный `all`, а также отказ при
неверном имени и очистку после ошибки генерации.

## Docker

Dockerfile только копирует готовый бинарник. Сборка выполняется локально:

```sh
mise run //modules/billing:build
docker build -t distributed-programming-billing:local modules/billing
```

`build` создаёт Linux-бинарник в `dist/billing`, с отключённым CGO.
`GOARCH` позволяет выбрать архитектуру вручную; `local-up` выбирает архитектуру
Docker-сервера. Образ запускает `service` по умолчанию; для consumer передаётся
команда `message-handler`.
