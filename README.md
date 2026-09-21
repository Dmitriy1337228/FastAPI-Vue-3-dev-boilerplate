# FastAPI + Vue 3 + PostgreSQL + Nginx — dev-boilerplate

Готовый шаблон для локальной разработки: Python/FastAPI на бэкенде, Vue 3 + Vite на фронтенде,
PostgreSQL как СУБД, Nginx как единая точка входа. Всё поднимается одной командой через Docker Compose.

> Команды выполняются в **WSL-терминале** (Ubuntu). Проект должен лежать в файловой системе WSL
> (не в `/mnt/c/...`) — иначе bind-монты будут работать медленно.

## Стек

| Слой | Технологии |
|---|---|
| Backend | Python 3.12, FastAPI, SQLAlchemy 2.x (async), asyncpg, uvicorn `--reload`, менеджер зависимостей **uv** |
| Frontend | Vue 3 (`<script setup>`), Vite 6, TailwindCSS 3 |
| БД | PostgreSQL 16 (named volume `postgres_data`) |
| Прокси | Nginx (stable-alpine) — единственная точка входа `:80` |

## Архитектура

```
Браузер ──► nginx :80
             ├── /api/*, /docs, /openapi.json ──► backend:8000 (FastAPI)
             └── всё остальное (+WebSocket Upgrade) ──► frontend:3000 (Vite dev server)
backend ──► db:5432 (PostgreSQL)
```

- Порт `3000` **не публикуется на хост** — к Vite можно попасть только через Nginx.
- Порт `8000` опубликован для прямого доступа к API, `5432` — для подключения к БД клиентом с хоста.
- HMR-WebSocket Vite проксируется через Nginx на `:80` (проверено: upgrade → `101 Switching Protocols`).

## Структура проекта

```
backend/
  Dockerfile.dev      # uv + python3.12-alpine; зависимости ставятся в /opt/venv при СБОРКЕ из uv.lock
  pyproject.toml      # зависимости backend (источник истины)
  uv.lock             # lockfile (генерируется uv, коммитится в git)
  main.py             # FastAPI: lifespan с retry-подключением к PostgreSQL; GET /api/v1/health
frontend/
  Dockerfile.dev      # node:20-alpine, БЕЗ `RUN npm install` (см. «Особенности»)
  package.json        # зависимости frontend (источник истины)
  package-lock.json   # lockfile (коммитится в git)
  vite.config.js      # host:0.0.0.0, port:3000, hmr.clientPort:80
  src/                # main.js, App.vue, main.css (Tailwind)
nginx/
  nginx.dev.conf      # правила маршрутизации + Upgrade/Connection для HMR
docker-compose.yml    # 4 сервиса: backend, frontend, nginx, db
.agent/check.sh       # скрипт приёмочных проверок (8 проверок, exit 0 при успехе)
```

---

## Первая сборка

```bash
cd /home/laravel/projects/fastapi_example
docker compose up -d --build
```

Что произойдёт:

1. Соберутся образы `backend` и `frontend` (frontend-образ собирается моментально — npm install в нём намеренно нет).
2. Поднимутся 4 контейнера. Nginx и backend стартуют почти сразу (backend сам дождётся БД: в compose есть
   healthcheck + retry-логика в lifespan).
3. **Frontend при первом старте выполнит `npm install` в свой anonymous volume — это занимает ~10 минут
   на этом хосте. Это НЕ зависание — дождитесь.** Логи npm буферизуются и появляются пачкой после завершения.

Прогресс первого npm install:

```bash
docker compose logs -f frontend
# ...может молчать несколько минут, потом вывести "added N packages" и "VITE ready"
```

После старта Vite в логах появится:

```
VITE v6.x.x  ready in ... ms
  ➜  Local:   http://localhost:3000/
```

## Запуск после сборки (ежедневный)

```bash
docker compose up -d          # старт (быстро: volume с node_modules сохранён)
docker compose stop           # остановка на вечер (volume сохраняется)
docker compose restart        # перезапуск
docker compose ps             # статус: 4 сервиса Up, db — healthy
```

**Важно:** используйте `stop`/`up -d` для повседневной работы. Команда `docker compose down`
удаляет контейнеры вместе с anonymous volume `/app/node_modules` → при следующем `up` npm install
пойдёт заново (~10 минут). `down -v` дополнительно стирает базу данных.

## Проверка работоспособности

```bash
wsl bash /home/laravel/projects/fastapi_example/.agent/check.sh   # из PowerShell
# или из WSL-терминала:
bash .agent/check.sh
```

Ожидается `PASS=8 FAIL=0`. Что проверяется:

| URL | Что должно быть |
|---|---|
| `http://localhost/` | 200 — Vue-приложение (тёмная страница, карточка «Hello World из Vue 3 + FastAPI», `GET /api/v1/health → {"status":"ok"}`) |
| `http://localhost/api/v1/health` | 200 + `{"status":"ok"}` |
| `http://localhost/docs` | 200 — Swagger UI |
| `http://localhost/openapi.json` | 200 — OpenAPI-схема |
| `http://localhost:8000/...` | те же endpoint'ы напрямую (мимо Nginx) |

---

## Разработка

### Backend: правка кода

Код монтируется с хоста (`./backend:/app`), uvicorn работает с `--reload` — **любые правки `.py`
подхватываются мгновенно, пересборка не нужна.**

### Backend: добавить зависимость (насовсем)

1. Добавьте пакет в `backend/pyproject.toml`:

   ```toml
   dependencies = [
       "fastapi",
       "uvicorn",
       "sqlalchemy[asyncio]",
       "asyncpg",
       "pydantic-settings",   # <-- новый
   ]
   ```

2. Регенерируйте `uv.lock` (uv есть только в контейнерном образе, на хост его ставить не нужно):

   ```bash
   cd backend
   docker run --rm -v "$PWD:/app" -w /app ghcr.io/astral-sh/uv:python3.12-alpine uv lock
   cd ..
   ```

3. Пересоберите backend:

   ```bash
   docker compose up -d --build backend
   ```

   Пересборка быстрая: кэш слоёв, заново выполнится только `uv sync` (докачает новый пакет).

Защита от рассинхрона: `uv sync --frozen` упадёт, если `pyproject.toml` и `uv.lock` не согласованы.
`uv.lock` руками не редактируется — только через `uv lock`.

### Backend: быстро потестировать пакет (без пересборки)

```bash
docker compose exec backend uv pip install <package>
```

Ставится в `/opt/venv` работающего контейнера. Переживёт `restart`, но **пропадёт** при пересоздании
контейнера — после успешного теста зафиксируйте пакет через `pyproject.toml` + `uv lock` + rebuild.

### Frontend: правка кода и HMR

Код монтируется с хоста, Vite отдаёт его через Nginx. Правьте `frontend/src/**` — браузер обновится
сам (HMR через `ws://localhost:80`, сервер подхватывает изменения без перезагрузки страницы).

### Frontend: добавить зависимость

`npm install` выполняется при **каждом старте контейнера** и приводит `node_modules` в соответствие
с `package.json`. Поэтому:

1. Добавьте пакет в `frontend/package.json`:

   ```json
   "dependencies": {
     "vue": "^3.5.0",
     "vue-router": "^4.5.0"
   }
   ```

2. Перезапустите frontend (пересборка образа НЕ нужна):

   ```bash
   docker compose restart frontend
   ```

3. Дождитесь установки (инкрементальный `npm install` быстрее первой полной; смотрите логи):

   ```bash
   docker compose logs -f frontend
   ```

Альтернатива одной командой (обновит и `package.json`, и `node_modules`; версия — на ваше усмотрение):

```bash
docker compose exec frontend npm install --no-audit --no-fund vue-router
```

Удаление зависимости — убрать её из `package.json` и сделать `restart` (npm удалит лишнее).

### База данных

Подключение из backend (уже настроено в `docker-compose.yml`):

```
postgresql+asyncpg://postgres:postgres@db:5432/app_db
```

psql внутри контейнера:

```bash
docker compose exec db psql -U postgres -d app_db
```

Подключение клиентом с хоста: `localhost:5432`, пользователь `postgres`, пароль `postgres`, БД `app_db`.

Полный сброс БД (удалит данные!): `docker compose down -v && docker compose up -d`
(заодно удалится и node_modules → долгий первый `npm install`).

---

## Особенности и известные ограничения

1. **Первый `npm install` медленный (~10 мин)** — особенность volume I/O на этом хосте. Это не зависание:
   процесс завершается. На инкрементальных установках — заметно быстрее.
2. **`RUN npm install` в `frontend/Dockerfile.dev` сознательно отсутствует** — buildkit на этом хосте
   зависает на этом шаге. Установка вынесена в `command` контейнера. Не добавляйте её обратно.
3. **Порт 3000 недоступен с хоста — так и задумано.** Единая точка входа — Nginx `:80`.
4. **Vite пускает только `localhost`.** Открытие по другому имени хоста (например, IP WSL) даст `403 Forbidden`
   — это защита `server.allowedHosts`. Чтобы разрешить имя, добавьте его в `vite.config.js`:

   ```js
   server: {
     host: true,
     port: 3000,
     allowedHosts: ['myhost.local'],   // не отключайте проверку полностью
     hmr: { clientPort: 80 },
   }
   ```

5. **Токен HMR регенерируется** при каждом старте Vite (нужен только для ручных WS-тестов, браузер получает его сам).
6. **Builder `desktop-linux` на этом хосте сломан** — сборки идут через builder `default`, это нормально.
7. **Терминал Windows/PowerShell:** не передавайте через `wsl bash -c '...'` строки с пробелами внутри
   кавычек и с `%{...}`/`{{...}}` — `wsl.exe` ломает квотинг. Для сложных команд — файл-скрипт +
   `wsl bash /путь/скрипт.sh` (как сделано в `.agent/check.sh`).

## Troubleshooting

| Симптом | Причина / решение |
|---|---|
| Логи frontend пустые несколько минут | stdout npm буферизуется; подождите — всё появится после завершения установки |
| `sh: vite: not found` | npm install ещё не дошёл до конца; проверьте `docker compose logs -f frontend` |
| Страница `localhost:3000` не открывается с хоста | Норма: порт не публикуется. Используйте `http://localhost/` |
| `403 Forbidden` на Vite-странице | Запрос пришёл с Host, которого нет в `allowedHosts` (см. выше) |
| Сборка backend падает на `uv sync --frozen` | `pyproject.toml` и `uv.lock` разошлись — выполните `uv lock` (см. выше) |
| `db` не healthy | `docker compose logs db`; volume `postgres_data` повреждён → крайний случай `down -v` (удалит данные) |
| Всё сломалось, начать с нуля | `docker compose down -v` → `docker compose up -d --build` (потеряете БД и ~10 минут на npm) |
