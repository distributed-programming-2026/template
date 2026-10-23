# Template service

Рабочий пример использования go-sdk и исходник для генератора новых модулей.

## Сценарий

```text
HTTP / gRPC → app → unit of work → echo + outbox (одна MySQL-транзакция)
                                             ↓
                                      relay → RabbitMQ
                                             ↓
                              message-handler → inbox → лог
```

HTTP: `POST /api/public/v1/echo` с JSON `{"body":"hello"}`. Ответ:
`{"operationID":"<uuid>"}`. Пустая строка допустима; поле `body` обязательно.

gRPC: `templateInternalAPI.TemplateService/Echo`, запрос `{"Body":"hello"}`,
ответ с `OperationID`. Сервер поддерживает reflection:

```sh
grpcurl -plaintext -d '{"Body":"hello"}' localhost:8081 \
  templateInternalAPI.TemplateService/Echo
```

Событие `templateEvents.Echo` содержит ID echo и исходную строку. SDK добавляет
envelope с event ID, producer, type, временем и correlation ID. Общий exchange
`domain-event` находится в `lib/event`; routing key модуля — `template.Echo`.

## Структура

- `cmd`: конфигурация, команды запуска и файлы сборки зависимостей по подсистемам: MySQL, миграции, AMQP, события и серверы.
- `internal/template/app`: транзакционная граница через SDK `UnitOfWorkWithRepositoryProvider`.
- `internal/template/domain`: echo-модель, бизнес-операция, интерфейс репозитория и payload события; используется нативный пакет `uuid` Go 1.27.
- `internal/template/infra/mysql`: repository provider; `repository` содержит реализацию echo-репозитория, `migrations` — миграции модуля.
- `internal/template/infra/handlers`: HTTP, gRPC и события.
- `internal/integration-tests`: инфраструктура, контейнеры и интеграционные проверки.
- `api`: protobuf/OpenAPI-контракты; generated Go-код исключён из Git.
- `config/gateway`: маршруты и объявления интерцепторов модуля для общего gateway.

Repository provider хранит транзакционный клиент и выдаёт репозиторий с контекстом
операции. `app` использует `ExecuteWithRepositoryProvider`; SQL-клиент в него не
передаётся. Outbox и репозиторий используют один context и один экземпляр UOW.

UUID в таблице `echo` хранится как `BINARY(16)`. В SQL-параметры передаётся
`uuid.UUID`: MySQL-клиент SDK преобразует его в 16 байт. В HTTP, gRPC и событиях
ID остаётся строкой.

## Пример интерцептора gateway

`internal/template/infra/handlers/gateway` реализует gRPC API интерцептора через
`lib/gateway/interceptor` и регистрируется на сервере
модуля (`8081`) вместе с internal API. `config/gateway/interceptor.yaml` объявляет
интерцептор, а `routes.yaml` подключает его к маршруту `/template/api/...`.
`local-up` автоматически собирает оба файла в конфигурацию gateway.

Пример показывает три решения:

- `requestHeaders`: устанавливает `X-Demo-Request-ID` из `context.requestId`, заменяя значение клиента.
- `responseHeaders`: добавляет `X-Demo-Interceptor: template` в ответ backend.
- `requestHeaders` с `X-Demo-Deny: true`: возвращает JSON с HTTP `403` через `immediateResponse`; backend и response-фаза не вызываются.

Это демонстрация API. Проверку заголовка `X-Demo-Deny` следует заменить политикой
приложения, если нужна авторизация или другая бизнес-проверка.

После `mise run local-up`:

```sh
curl -i -X POST localhost/template/api/public/v1/echo \
  -H 'Content-Type: application/json' -d '{"body":"through gateway"}'
curl -i -X POST localhost/template/api/public/v1/echo \
  -H 'Content-Type: application/json' -H 'X-Demo-Deny: true' -d '{"body":"denied"}'
```

Первый ответ содержит `X-Demo-Interceptor: template`, второй — `403`.
Для отключения примера удалите `interceptors` у маршрута. При обращении к HTTP
порту модуля напрямую интерцептор не вызывается.

## Запуск

Из корня репозитория:

```sh
mise run local-up
```

Корневой mise автоматически подключает модульный `compose.yaml`, собирает бинарник
и поднимает сервис и consumer в контейнерах.

Конфиги из `config/gateway/` автоматически собираются вместе с конфигами
остальных модулей при `local-up`. Общие настройки gateway находятся в корневом
`config/gateway/`. Маршрут `/template/api/...` проксируется на
`template-service:8082`, удаляя префикс `/template`:

```sh
curl -X POST localhost/template/api/public/v1/echo \
  -H 'Content-Type: application/json' -d '{"body":"hello"}'
```

После изменения конфигов повторите `mise run local-up` для перезапуска gateway.

Бинарник поддерживает `service` (по умолчанию) и `message-handler`.
`service` запускает HTTP, gRPC и relay. `message-handler` запускает consumer
и HTTP `/healthz`. Health endpoint отвечает 204 и проверяет liveness.

## Конфигурация

| Переменная | Значение по умолчанию |
| --- | --- |
| `TEMPLATE_APP_DEBUG` | `false` |
| `TEMPLATE_APP_GRACE_TIMEOUT` | `30s` |
| `TEMPLATE_HTTP_ADDRESS` | `:8082` |
| `TEMPLATE_GRPC_ADDRESS` | `:8081` |
| `TEMPLATE_MYSQL_ADDRESS` | `localhost:3306` |
| `TEMPLATE_MYSQL_DATABASE` | `template` |
| `TEMPLATE_MYSQL_USER` | `template` |
| `TEMPLATE_MYSQL_PASSWORD` | `template` |
| `TEMPLATE_MYSQL_MAX_CONNECTIONS` | `10` |
| `TEMPLATE_MYSQL_CONNECTION_MAX_LIFETIME` | `30m` |
| `TEMPLATE_MYSQL_CONNECTION_MAX_IDLE_TIME` | `5m` |
| `TEMPLATE_MYSQL_CONNECT_TIMEOUT` | `5s` |
| `TEMPLATE_MYSQL_READ_TIMEOUT` | `10s` |
| `TEMPLATE_MYSQL_WRITE_TIMEOUT` | `10s` |
| `TEMPLATE_AMQP_URL` | `amqp://local:local@localhost:5672/` |
| `TEMPLATE_AMQP_QUEUE` | `template.echo` |
| `TEMPLATE_AMQP_CONNECT_TIMEOUT` | `5s` |
| `TEMPLATE_AMQP_PREFETCH_COUNT` | `10` |
| `TEMPLATE_RELAY_INTERVAL` | `1s` |
| `TEMPLATE_RELAY_BATCH_SIZE` | `100` |
| `TEMPLATE_RELAY_PUBLISH_TIMEOUT` | `10s` |
| `TEMPLATE_RELAY_LOCK_TIMEOUT` | `1s` |

DSN формируется рядом с connector через `mysqldriver.Config.FormatDSN()`;
`parseTime` и `utf8mb4` включаются там же. `--debug` также включает подробные логи.
Новые модули используют свой env-префикс.

## Миграции и сборка

```sh
mise run //modules/template:generate-migration "Create a new table"
mise run //modules/template:build
```

Генератор создаёт и регистрирует новую миграцию. Реализуйте `Up`: начальная
заглушка возвращает ошибку. Обе команды сервиса применяют все таргеты миграций:
модуль, outbox и inbox.

`build` генерирует контракты и локально собирает Linux-бинарник `dist/template`.
Dockerfile только копирует его в образ. Для нативного запуска используйте задачу
`run`, для выбора архитектуры Linux-сборки — `GOARCH`.

## Гарантии

Успех API означает commit echo и outbox. Ошибка внутри транзакции откатывает обе
записи. Повторный API-запрос создаёт новый echo.

Оба процесса объявляют durable-очередь. Relay использует publisher confirms и
повторяет неудавшиеся публикации. API сохраняет операции при потере RabbitMQ
после запуска; backlog отправляется после восстановления соединения. Ошибка
подключения при первоначальном запуске останавливает процесс.

Доставка at-least-once. Inbox подавляет повторную обработку зафиксированных
`(consumer, event_id)`. Логирование не атомарно с commit inbox: при сбое возможен
повторный лог. Ошибки consumer и невалидные события попадают в `<queue>.dead`
через общий exchange `domain-event.dead`. Автоматический retry consumer не включён.

HTTP и gRPC принудительно закрываются после grace timeout и возвращают ошибку,
для которой `errors.Is(err, context.DeadlineExceeded)` истинно.
Очистка outbox/inbox через SDK `Cleanup` в пример не входит.

## Проверки

```sh
mise run //modules/template:all
mise run //modules/template:integration-tests
```

Интеграционные тесты проверяют HTTP и gRPC API, запись события в outbox,
обработку через inbox, повторную доставку и некорректные HTTP-запросы.
Задача mise собирает Linux-бинарник и Docker-образ. Testcontainers запускает
сервис и consumer из этого образа вместе с MySQL и RabbitMQ в отдельной сети.
Тестовый MySQL-пароль содержит специальные символы для проверки DSN.
