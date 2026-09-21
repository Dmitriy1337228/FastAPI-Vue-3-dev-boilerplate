# HANDOFF — FastAPI + Vue3 + PostgreSQL + Nginx dev-boilerplate

Дата: 2026-09-21 (~19:30).

## STATUS: ✅ ЗАВЕРШЕНО — все критерии ТЗ выполнены, проверены, проект вычищен

Блокер из предыдущей сессии («висящий npm install») оказался не блокером:
`npm install` в контейнере frontend **завершился сам** за ~11 минут (медленно, но не завис) —
см. лог: `added 82 packages, removed 124 packages, and changed 35 packages in 11m`.
После этого Vite v6.4.3 стартовал и слушает `0.0.0.0:3000`. Шаги A/B из старого плана
(диагностика зависшего npm, ручной запуск vite) не потребовались.

## Итоговое состояние (проверено фактически, не по логам прошлой сессии)

- `docker compose ps` — 4×Up: `backend`, `db` **(healthy)**, `frontend` (Vite 6.4.3, порт 3000 внутри сети), `nginx` (:80).
- Логи backend: `Application startup complete` — подключение к PostgreSQL успешно.
- Приёмочные проверки: `.agent/check.sh` → **PASS=8 FAIL=0**:

| Проверка | URL | Результат |
|---|---|---|
| frontend через Nginx | `http://localhost/` | 200, отдаётся index.html Vite |
| API health через Nginx | `http://localhost/api/v1/health` | 200 + `{"status":"ok"}` (proxy_pass без URI — путь сохранён) |
| Swagger UI через Nginx | `http://localhost/docs` | 200 |
| OpenAPI через Nginx | `http://localhost/openapi.json` | 200 |
| backend напрямую | `http://localhost:8000/docs` | 200 |
| backend health напрямую | `http://localhost:8000/api/v1/health` | 200 + `{"status":"ok"}` |
| Vite-модуль через Nginx | `http://localhost/src/main.js` | 200 (трансформация модулей работает) |
| Vite HMR client через Nginx | `http://localhost/@vite/client` | 200 (182 KB) |

- **HMR WebSocket подтверждён протокольным тестом** (не только конфигом):
  upgrade с заголовками `Upgrade: websocket` + `Sec-WebSocket-Protocol: vite-hmr` и валидным токеном
  через Nginx :80 → `HTTP/1.1 101 Switching Protocols` + фрейм `{"type":"connected"}` от Vite.
  Контрольный тест напрямую к `frontend:3000` внутри сети даёт идентичный ответ — апгрейд проходит
  через nginx корректно (nginx.dev.conf: `proxy_http_version 1.1` + `Upgrade`/`Connection`).
  Токен извлекается из `/@vite/client` (`wsToken = "..."`, регенерируется при перезапуске Vite).
  Browser-тест по-прежнему не проводился (нет browser automation), но протокольное доказательство есть.

## Важные наблюдения (чтобы не тратить время повторно)

1. **npm install медленный на этом хосте, но НЕ зависает в runtime-контейнере.**
   Первая установка в свежий anonymous volume: ~11 мин. Не «лечить», просто ждать.
2. **`RUN npm install` в Dockerfile (buildkit) на этом хосте НЕ использовать** — зависает (подтверждено
   прошлой сессией). Оставлено как есть: `npm install` выполняется в compose `command` при старте контейнера.
3. **Порт 3000 не публикуется на хост — это намеренно.** Единственная точка входа — Nginx :80.
   Прямой запрос из WSL на `localhost:3000` даст connection refused — это не ошибка.
4. **Прямой запрос к `frontend:3000` с `Host: frontend:3000` → 403 Forbidden** — это защита
   Vite `server.allowedHosts` (по умолчанию разрешён только localhost). Через Nginx Host переписывается
   на `localhost` → работает. Для доступа по другому имени хоста добавить его в `vite.config.js`
   (`server.allowedHosts`), не отключать проверку полностью.
5. **Токен HMR** не статический — берётся из `/@vite/client` и меняется при каждом старте Vite.

## Ограничение по ТЗ: anonymous volume `/app/node_modules`

- `docker compose down` удаляет anonymous volume → при следующем `up` npm install пойдёт заново (~10+ мин).
- `docker compose restart` / `up -d` (без down) volume сохраняют — рестарт быстрый.
- Если скорость первого старта станет проблемой — перейти на named volume (отступление от ТЗ) — сознательно НЕ сделано.

## Уборка (выполнена)

- Удалены артефакты отладки прошлой сессии из корня проекта: `package.json` (битый), `package-lock.json`, `node_modules/` (след host-установки npm).
- Удалена временная папка `_diag/` (все скрипты диагностики).
- **Добавлен постоянный скрипт приёмки `.agent/check.sh`** — прогон всех 8 проверок, exit code 0 при успехе:
  `wsl bash /home/laravel/projects/fastapi_example/.agent/check.sh`
- `frontend/package-lock.json` оставлен (создан npm install, согласован с `frontend/package.json`: vite 6.4.3, 169 пакетов) — фиксирует версии.
- **Добавлен `README.md`** — описание проекта, первая сборка, ежедневные кейсы, добавление зависимостей
  фронта/бэка, особенности хоста, troubleshooting.

## Структура проекта (финальная)

```
backend/   Dockerfile.dev (uv, python3.12-alpine), pyproject.toml, uv.lock, main.py (lifespan + /api/v1/health)
frontend/  Dockerfile.dev (node:20-alpine, без RUN npm install), package.json, package-lock.json,
           vite.config.js (host:true, port:3000, hmr.clientPort:80), index.html, postcss.config.js,
           src/{main.js, App.vue, main.css}
nginx/     nginx.dev.conf (/api/, /docs, /openapi.json -> backend:8000; / -> frontend:3000 + Upgrade)
.agent/    HANDOFF.md, check.sh (скрипт приёмки)
README.md  описание проекта, первый запуск, ежедневные кейсы, зависимости фронта/бэка, troubleshooting
docker-compose.yml   backend, frontend, nginx, db (postgres_data named volume, healthcheck)
.gitignore
```

## Если понадобится продолжить работу

```bash
wsl bash /home/laravel/projects/fastapi_example/.agent/check.sh          # приёмка
wsl bash -c 'cd /home/laravel/projects/fastapi_example && docker compose ps'
wsl bash -c 'cd /home/laravel/projects/fastapi_example && docker compose logs frontend'
wsl bash -c 'cd /home/laravel/projects/fastapi_example && docker compose up -d --build'
```

⚠️ Терминал — PowerShell (win32): НЕ передавать через `wsl bash -c '...'` строки с пробелами внутри
кавычек и с `%{...}`/`{{...}}` — `wsl.exe` ломает квотинг (аргументы режутся по пробелам). Для таких
команд — скрипт-файл + `wsl bash /путь/скрипт.sh`.

Оставшиеся не-автоматизируемые пункты: browser-тест HMR в реальном браузере (нет browser automation).