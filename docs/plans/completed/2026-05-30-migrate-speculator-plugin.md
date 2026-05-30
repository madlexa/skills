# Перенос speculator в репозиторий skills как плагин Claude Code

## Overview

Перенос проекта speculator (graph-oriented knowledge base, TypeScript CLI + MCP server) в текущий репозиторий skills и рефакторинг из standalone TypeScript-проекта в полноценный плагин Claude Code по примеру плагина niblet. Цель — единая структура плагина, пригодная для публикации через marketplace.

Исходный код уже скопирован в `temp/speculator/` (предыдущая сессия). Целевая директория — `plugins/speculator/`.

## Context

### Текущая структура speculator (в temp/speculator/)
- TypeScript CLI + MCP server: `src/cli.ts`, `src/mcp.ts`
- Команды: `src/commands/*.ts` (add, get, list, search, update, init, stats, setup, validate, export, remove, registry, index, import)
- Утилиты: `src/lib/*.ts` (graph, document, index-reader, prompts, constants, command-utils, tool, date-utils, path-formatter)
- Агенты: `agents/speculator-ai-engineer.md`, `agents/speculator-mcp-protocol-engineer.md`, `agents/speculator-typescript-cli-developer.md`
- Инструкции: `AGENTS.md`, `CLAUDE.md`
- Сборка: `tsconfig.json`, `package.json`, `dist/cli.js`, `dist/mcp.js`
- Настройка через `.claude/settings.json` (hooks)
- Публикация как npm-пакет

### Целевая структура плагина (как niblet, в plugins/niblet/)
- `.claude-plugin/plugin.json` — манифест плагина
- `hooks/hooks.json` + `hooks/*.sh` — регистрация и реализация хуков (bash)
- `skills/speculator/SKILL.md` — описание skill
- `agents/*.md` — агенты (перенос из speculator/agents/)
- `bin/` — CLI-обёртки (bash wrapper для compiled JS)
- `lib/` — библиотечные bash-функции для хуков
- `tests/smoke_test.sh` — smoke-тесты

### Related patterns
- Структура и соглашения берутся из `plugins/niblet/` (plugin.json, hooks.json, bin wrapper, lib/paths.sh, tests/smoke_test.sh).
- Корневой `.claude-plugin/marketplace.json` — для регистрации плагина в marketplace.

### Dependencies
- Node.js + npm (TypeScript-сборка speculator).
- Внешние npm-зависимости speculator (zod, pkce-challenge, tinyglobby и пр.) — переносятся через package.json.

## Development Approach

- **Testing approach**: Regular (код сначала, затем тесты).
- Завершать каждую задачу полностью перед переходом к следующей.
- Структуру плагина копировать с niblet как с эталона; не изобретать новые соглашения.
- **CRITICAL: каждая задача ДОЛЖНА включать новые/обновлённые тесты.**
- **CRITICAL: все тесты должны проходить перед началом следующей задачи.**

## Implementation Steps

### Task 1: Создать базовую структуру плагина

**Files:**
- Create: `plugins/speculator/.claude-plugin/plugin.json`
- Create: `plugins/speculator/README.md`
- Create: `plugins/speculator/package.json`

- [x] Создать директорию `plugins/speculator/`
- [x] Создать `plugin.json` с метаданными (имя, версия, описание) по образцу `plugins/niblet/.claude-plugin/plugin.json`
- [x] Создать `README.md` с документацией по установке и использованию
- [x] Создать `package.json` для зависимостей TypeScript/NPM (перенести deps из `temp/speculator/package.json`)
- [x] write tests: проверить что `plugin.json` валиден (jq parse) — добавить в будущий smoke_test
- [x] run tests — должны проходить (jq -e parse plugin.json + package.json, версии совпадают 0.1.5)

### Task 2: Перенести исходный код TypeScript

**Files:**
- Create: `plugins/speculator/src/cli.ts`
- Create: `plugins/speculator/src/mcp.ts`
- Create: `plugins/speculator/src/commands/*.ts` (все команды)
- Create: `plugins/speculator/src/lib/*.ts` (все утилиты)
- Create: `plugins/speculator/tsconfig.json`

- [x] Скопировать все `.ts` файлы из `temp/speculator/src/` (25 файлов: cli.ts, mcp.ts, 14 commands, 9 lib)
- [x] Перенести `tsconfig.json`, обновить пути при необходимости (структура идентична, пути не менялись)
- [x] Обновить пути импортов, если изменилась структура (импорты относительные ./commands ./lib — изменений не требуется)
- [x] write tests: `npx tsc --noEmit` компилируется без ошибок
- [x] run tests — должны проходить (npx tsc --noEmit exit 0)

### Task 3: Создать CLI wrapper как в niblet

**Files:**
- Create: `plugins/speculator/bin/speculator`
- Modify: `plugins/speculator/package.json` (scripts)

- [x] Создать `bin/speculator` — bash wrapper для запуска compiled `dist/cli.js`
- [x] Добавить логику поиска `dist/cli.js` (plugin root -> local dev), как в `plugins/niblet/bin/` (CLAUDE_PLUGIN_ROOT -> plugin root)
- [x] Сделать исполняемым (`chmod +x`)
- [x] write tests: запуск `bin/speculator --help` возвращает 0 и выводит usage (tests/bin_test.sh)
- [x] run tests — должны проходить (tests/bin_test.sh exit 0)

### Task 4: Создать систему хуков по примеру niblet

**Files:**
- Create: `plugins/speculator/hooks/hooks.json`
- Create: `plugins/speculator/hooks/on_session_start.sh`
- Create: `plugins/speculator/hooks/on_prompt_submit.sh`

- [x] Создать `hooks.json` с регистрацией `SessionStart` и `UserPromptSubmit` (формат как в `plugins/niblet/hooks/hooks.json`)
- [x] Создать `on_session_start.sh` — вывод информации о knowledge base (speculator stats по KB_DIR)
- [x] Создать `on_prompt_submit.sh` — интеграция с поиском по графу (speculator search по тексту промпта)
- [x] Сделать скрипты исполняемыми (chmod +x)
- [x] write tests: каждый хук запускается без ошибок (exit 0) на пустом окружении (tests/hooks_test.sh)
- [x] run tests — должны проходить (tests/hooks_test.sh exit 0)

### Task 5: Создать skill и перенести агентов

**Files:**
- Create: `plugins/speculator/skills/speculator/SKILL.md`
- Create: `plugins/speculator/agents/speculator-ai-engineer.md`
- Create: `plugins/speculator/agents/speculator-typescript-cli-developer.md`
- Create: `plugins/speculator/agents/speculator-mcp-protocol-engineer.md`

- [x] Создать `SKILL.md` на основе `temp/speculator/AGENTS.md` (frontmatter с name/description как в niblet SKILL.md)
- [x] Перенести трёх агентов из `temp/speculator/agents/`
- [x] Обновить ссылки и пути в агентах под новую структуру плагина (CLI → `speculator`/`bin/speculator`; убрана пустая строка перед frontmatter в typescript-cli агенте; src/ пути остаются валидны в plugin root)
- [x] write tests: SKILL.md и каждый агент имеют валидный YAML frontmatter (name + description) — tests/frontmatter_test.sh
- [x] run tests — должны проходить (tests/frontmatter_test.sh exit 0)

### Task 6: Создать библиотечные функции (lib/)

**Files:**
- Create: `plugins/speculator/lib/paths.sh`
- Create: `plugins/speculator/lib/graph.sh`

- [x] Создать `paths.sh` с функциями определения project root (speculator_project_root/kb_dir/plugin_root/field/cwd_from_stdin, по образцу `plugins/niblet/lib/paths.sh`)
- [x] Создать `graph.sh` с функциями поиска по графу, вызываемыми из хуков (speculator_bin/kb_has_md/graph_ready/stats/search; оба хука отрефакторены на использование lib)
- [x] write tests: source `paths.sh`/`graph.sh` без ошибок, функция project-root возвращает корректный путь (tests/lib_test.sh)
- [x] run tests — должны проходить (lib_test + регрессия hooks/bin/frontmatter exit 0; e2e: хуки эмитят stats/search через lib)

### Task 7: Сборка и smoke-тесты

**Files:**
- Modify: `plugins/speculator/package.json` (scripts: build, test, typecheck)
- Create: `plugins/speculator/tests/smoke_test.sh`

- [x] Добавить scripts `build`, `test`, `typecheck` в `package.json` (build/typecheck присутствовали; `test` переключён на `bash tests/smoke_test.sh`, vitest сохранён как `test:unit`)
- [x] Собрать проект: `npm run build` (генерирует `dist/cli.js` + `dist/mcp.js` через esbuild)
- [x] Создать `tests/smoke_test.sh` с проверками из задач 1–6 (plugin.json/package.json валидны + версии совпадают, tsc --noEmit, делегирует bin_test/hooks_test/frontmatter_test/lib_test)
- [x] run tests: `npm test` / `tests/smoke_test.sh` — проходят (exit 0, все 6 секций зелёные)

### Task 8: Зарегистрировать плагин и обновить корневую документацию

**Files:**
- Modify: `.claude-plugin/marketplace.json` (корневой)
- Modify: `README.md` (корневой)

- [x] Добавить speculator в `marketplace.json` (имя, версия 0.1.5, source ./plugins/speculator, описание + keywords — по образцу записи niblet)
- [x] Добавить speculator в список плагинов в корневом `README.md` (секция "### speculator (v0.1.5)" + добавлен в примеры /plugin install)
- [x] Добавить инструкции по установке speculator как плагина (команды /plugin install и требование Node.js ≥ 20)
- [x] write tests: `marketplace.json` валиден (jq) и содержит запись speculator (tests/marketplace_test.sh: валидный JSON, наличие записи, source резолвится в plugin dir, версия совпадает с plugin.json)
- [x] run tests — должны проходить (marketplace_test.sh exit 0; smoke_test.sh — все 7 секций зелёные)

### Task 9: Verify acceptance criteria

- [x] run full test suite: `cd plugins/speculator && npm test` (exit 0, все 7 секций smoke_test зелёные)
- [x] run typecheck/linter: `cd plugins/speculator && npx tsc --noEmit` (exit 0, нет ошибок типов)
- [x] verify: `plugin.json` и `marketplace.json` согласованы по версии (0.1.5 в plugin.json/marketplace.json/package.json)
- [x] verify: все хуки запускаются без ошибок (on_session_start.sh + on_prompt_submit.sh exit 0 на пустом окружении)

### Task 10: Update documentation

- [x] update `plugins/speculator/README.md` финальной документацией (добавлена секция Hooks: on_session_start/on_prompt_submit; установка, CLI reference, MCP уже были)
- [x] add `plugins/speculator/CHANGELOG.md` (перенесён из `temp/speculator/CHANGELOG.md`, добавлена запись Packaging о репакете в плагин под 0.1.5)
- [x] update корневой `README.md` если изменился список плагинов (список не менялся — speculator v0.1.5 уже присутствует и актуален; правок не требуется)

## Post-Completion (manual verification)

- Установить плагин локально через `/plugin install` и проверить, что хуки и skill активируются.
- Проверить работу MCP-сервера speculator в реальной сессии.
- Удалить `temp/speculator/` после успешного переноса.
