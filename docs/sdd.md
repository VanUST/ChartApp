# System Design Document (SDD) v0.1 — «ChartApp»

> **Статус:** принят как основание для Phase 0. Это единственный документ решений в
> репозитории: ADR не ведутся (решение владельца проекта), поэтому D1–D7 и все последующие
> решения фиксируются здесь разделом «Журнал решений».
>
> Документ описывает **почему** система устроена так, а не **что** реализовано. Контракты
> отдельных модулей живут inline, рядом с кодом, в блоках PURPOSE/INPUTS/OUTPUTS/KEYWORDS;
> этот файл их не дублирует.

База: решения D1–D7 (touch-parity, structured reflow + object-anchored annotations, Flutter +
native ink, local-first event-sourced, iReal-импорт в v1, бесплатно для базы тестеров).

---

## 1. High-level architecture

```
┌──────────────────────────── CLIENT (Flutter app) ────────────────────────────┐
│  Presentation:  Library │ Editor(canvas+docks+outline) │ Scene │ Setlists    │
│  State:         Riverpod-контроллеры, ToolStateMachine, GestureArbiter       │
│  Application:   UseCases (ImportIReal, TransposeSong, BuildSetlist, Share…)  │
│  ┌─────────────────────────── chart_core (pure Dart) ─────────────────────┐  │
│  │ Song-модель │ ChordGrammar │ Transposer │ LayoutEngine │ IRealCodec │  │
│  │ OpLog (event-sourcing) │ SpellingTable │ SetlistModel │ FileFormats │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│  Infrastructure:  storage_drift (SQLite) │ ink_native (federated plugin) │   │
│                   pdf_export │ telemetry (LDD sinks) │ share_service        │
│  Native modules:  ink_native_ios (PencilKit) │ ink_native_android (InkView) │
└──────────────────────────────────────────────────────────────────────────────┘
        │ v1: НЕТ сервера (local-first, шеринг файлами .chart/.setlist)
        │ v1.5: SyncService (контракт зафиксирован сейчас, реализация позже)
┌───────▼──────────────────────── BACKEND (v1.5, контракт сейчас) ─────────────┐
│  Sync API: pushEvents/pullEvents/getSnapshot/createShareLink (append-only)   │
│  Postgres (docs, events, blobs) + auth magic-link; за интерфейсом SyncService │
│  Telemetry ingestion: POST /v1/events (batch jsonl); v1 = LocalFileSink       │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Ключевое:** весь домен живёт в `chart_core` без зависимостей от Flutter/SQLite → тестируется
на ПК без устройств, переиспользуется сервером в v1.5 для валидации событий.

---

## 2. Репозиторий (monorepo)

Раскладка соответствует SDD; отличия от первой редакции зафиксированы в журнале решений.

```
ChartApp/
├─ apps/mobile/                     # Flutter-приложение (android, ios, linux, windows)
├─ packages/
│  ├─ chart_core/                   # модели, транспозер, layout, codec, op-log
│  ├─ chart_ui/                     # дизайн-система, docks, жесты, focus-ribbon
│  ├─ ink_native/                   # federated plugin
│  │  ├─ ink_native/                #   app-facing пакет
│  │  ├─ ink_native_platform_interface/
│  │  ├─ ink_native_ios/            #   Swift + PencilKit
│  │  └─ ink_native_android/        #   Kotlin InkView
│  ├─ storage_drift/                # схемы SQLite, репозитории, миграции
│  └─ telemetry/                    # LDD: схемы событий, батчинг, sinks
├─ tools/
│  ├─ spike_harness/                # исполняемые спайки S1–S5
│  └─ logview/                      # CLI-анализатор JSONL (агрегаты, p50/p95)
├─ docs/
│  ├─ sdd.md                        # этот документ
│  ├─ ux/                           # легенда жестов, tap-бюджеты, экраны, протокол тестов
│  └─ fixtures/                     # РУЧНАЯ транскрипция 3 эскизов в JSON-фикстуры
├─ bootstrap.ps1 / bootstrap.sh     # настройка окружения (Windows / Linux)
├─ lefthook.yml                     # pre-commit
└─ .github/workflows/               # CI
```

**Правило для агентов:** фикстуры эскизов («Бумажный змей», «Иностранные слова»,
«Cm-медлей») транскрибируются в JSON вручную в Phase 0 — они становятся источником истины для
golden-тестов рендера и ожиданий транспозера/кодека.

---

## 3. Данные: схемы и форматы

### 3.1 Op-log (ядро event-sourcing, D6)

```json
{"v":1,"seq":42,"deviceId":"…","ts":"…","type":"chord.insert",
 "anchor":{"sectionId":"s1","bar":3,"beat":1.0},
 "payload":{"root":"C","quality":"m7","alt":[],"slash":null,"paren":false},
 "inverse":"chord.delete"}
```

- Undo/redo = append inverse-события (аудит бесплатно); redo-стек в памяти.
- Snapshot = свёртка событий до `seq N`; хранение: snapshot + хвост событий.

### 3.2 SQLite (drift)

`documents(id,title,key,bpm,updated_at,snapshot_json,snapshot_seq)` ·
`document_events(doc_id,seq,device_id,ts,type,json) idx(doc_id,seq)` ·
`ink_blobs(id,doc_id,anchor_json,format,path)` · `setlists(id,title)` ·
`setlist_items(setlist_id,pos,doc_id,transpose_sem,notes)` · `meta(k,v)`.

### 3.3 Файлы шеринга

`.chart` / `.setlist` = ZIP: `manifest.json` (format, v) + `snapshot.json` +
`events.jsonl` (хвост) + `ink/*.bin`. Импорт = merge событий; конфликт версий формата →
явная ошибка с логами, не молчаливая порча.

### 3.4 Anchors (D3)

Аннотация = `{anchor:{sectionId,bar,beat,step?}, offsetLocal, kind:ink|stamp|cue, payload}`.
Координаты вычисляются LayoutEngine-ом из bbox цели → переживают транспозицию/reflow/reorder.

---

## 4. Frontend: пайплайны рендера и ввода

**Layout:** `Song → SectionPlanner (play-order для сцены; edit показывает структуру со знаками) →
BarLayout (ширины по контенту) → SystemBuilder → PageBuilder → PageLayout`. Кэш: layout секции
keyed by `(sectionId, contentHash, widthBucket)`; рендер страницы = `ui.Picture`-кэш,
инвалидация по событиям, затронувшим страницу. Цель S4: < 16 мс/страница.

**Editor state:** `ToolStateMachine {SELECT, INPUT(chord|note|structure|stamp),
INK(pen|hl|eraser)}` + `GestureArbiter` (pen→ink, 1 палец SELECT→pan, 2 пальца→zoom/pan всегда)
+ курсор вставки с auto-advance + sticky-параметры (D2).

**Ink overlay:** PlatformView внутри того же transform-узла, что и canvas (единая Matrix4
scroll/zoom; Android — Hybrid Composition).

Контракт плагина зафиксирован в `ink_native_platform_interface`:
`initialize/setTool/setTransform/loadStrokes/exportStrokes` + поток
`onStrokeCommitted(blobId, bboxCenter)` → app вычисляет anchor от bboxCenter. Штрихи хранятся в
anchor-local координатах.

**State management:** Riverpod (code-gen, тестируемость). Решение D8.

---

## 5. Backend: v1 = интерфейс, v1.5 = реализация

- `SyncService` (interface в application layer): `pushEvents(docId,fromSeq,events[])`,
  `pullEvents(docId,afterSeq)`, `getSnapshot`, `createShareLink`. v1-имплементации:
  `NullSyncService`, `FileShareService` (.chart через системный share-sheet).
- v1.5: Postgres-append-only логов + magic-link auth; рекомендация — Supabase-совместимая схема
  за интерфейсом (возможен self-host). Конфликты: per-doc «чужие события поверх», UI-merge позже.
- **Telemetry (LDD):** `TelemetrySink` interface; v1 = `LocalFileSink` (rotating jsonl, батч при
  сохранении, sampling в bench-режимах) + отключаемый `HttpSink`. Никакой персональной
  информации: только события редактора и метрики.

---

## 6. Пайплайн тестирования

| Уровень | Что | Инструмент | Gate |
|---|---|---|---|
| L0 unit | chart_core: транспозер (property: round-trip 12 ключей), chord-grammar, codec-fuzz, op-log merge | dart test | coverage core ≥ 90%, CI-block |
| L1 golden | рендер фикстур 3 эскизов → PNG | flutter golden | pixel-diff = 0 (шрифт pinned) |
| L2 widget/integration | **tap-бюджеты как тесты**: «диатонический аккорд = 1 тап», «нота = 1 тап», вольта = ≤2 | flutter_test + patrol | fail при превышении бюджета |
| L3 device bench | ink p50/p95 (touch→present timestamps), fps, cold-open | harness `--bench` на Tab S8+/телефоне → JSONL → logview | пороги ниже |
| L4 usability | 5 музыкантов, задачи T1–T5, SUS, телеметрия тапов | протокол docs/ux/test-protocol.md | SUS ≥ 80, время сборки эскиза ≤ 5 мин |

**Пороги приёмки:** ink iOS PencilKit p95 ≤ 30 мс; Android S Pen p95 ≤ 45 мс; finger ≤ 60 мс;
layout < 16 мс/стр; cold-open p95 < 1000 мс; codec: структура 100%, аккорды ≥ 99%.

**CI:** `lint+format+test` (ubuntu, включая flutter-тесты) → android **debug APK build** →
ios **build-only + gate** (macos-runner; Xcode на ПК нет) → bench-джоба `workflow_dispatch /
device-required` с загрузкой логов артефактом.

**Матрица устройств:** ПК (dart test / flutter test / golden, плюс desktop-таргеты для
живого отклика) · Android-телефон (touch-UX) · **Galaxy Tab S8+** (S Pen, 120 Hz — эталон
ink-бенчей; включить 120 Гц в настройках) · iPhone знакомых (TestFlight-сборки с CI
mac-runner, после регистрации Apple Dev).

> Расхождение с первой редакцией: полноценный эмуляторный прогон на API 34 в CI заменён на
> сборку debug APK, потому что интеграционных тестов пока не существует и эмулятор без
> проверок стоит минуты, ничего не доказывая. Шаг с `android-emulator-runner` возвращается в
> тот же workflow, когда появится первый тест в `apps/mobile/integration_test`.

---

## 7. Developer environment

`bootstrap.ps1` (Windows) и `bootstrap.sh` (Linux/macOS) выполняют одни и те же шаги в одном
порядке и печатают `KEY=VALUE`, поэтому упавший bootstrap называет конкретный шаг:

```
GIT=2.51.2.windows.1
FLUTTER=3.47.7 (fvm-link)
DART=3.13.5
JDK=17
ANDROID_SDK=ok (C:\src\android-sdk)
WORKSPACE=ok
VERIFY=pass
BOOTSTRAP=ok
```

Шаги: Git (+`core.longpaths` на Windows) → Flutter пинованной версии из `.fvmrc` → Dart (идёт в
SDK) → JDK 17 → Android SDK → резолв workspace → `melos run verify`.

Скрипты **ничего не скачивают**: установка SDK — намеренное действие, поэтому bootstrap
сообщает, чего не хватает, и печатает команду исправления. Идемпотентны.

**Команды:**

| Команда | Что делает |
|---|---|
| `melos run verify` | Приёмочный gate: lint + format-check + тесты |
| `melos run lint` | Только статический анализ |
| `melos run format-fix` | Привести файлы к форме `dart format` |
| `melos run test-dart` | Тесты пакетов, которым Flutter не нужен |
| `melos run test-flutter` | Widget/golden-тесты Flutter-пакетов |
| `dart run logview <file.jsonl> --metric <path> --agg p50,p95` | Отчёт по bench-логу |

Конвенция коммитов: `feat(core-transposer): …`; ветки `feat|fix|spike/<pkg>-<task>`.

**DoD агента:** `melos run verify` зелёный + логи приложены + inline-контракт обновлён тем же
изменением + ADR не требуется (см. журнал решений).

---

## 8. Work breakdown

- **Phase 0:** скелет monorepo, CI, bootstrap, logview, контракт ink-плагина. **ADR не ведутся.**
  Фикстуры 3 эскизов — блокированы до получения эскизов от владельца.
- **Phase 1 (спайки):** S1 iReal codec · S3 transposer · S4 layout (core, без устройств) →
  S2 ink (Tab S8+) → S5 storage cold-open. Решения по логам.
- **Phase 2:** вертикальный срез: Library → Editor (chord-input, курсор, docks) → Scene pager.
- **Phase 3:** ink-интеграция, штампы/cue, outline-структура, мелодия (staff/name), сет-листы,
  PDF, iReal-import UI, share .chart.
- **Phase 4:** hardening, usability L4, бета (Play internal + TestFlight).

---

## 9. Журнал решений

Заменяет ADR. Каждая запись — дата, решение, причина. Новые записи добавляются сюда.

### D1–D7 (базовые, из постановки)

touch-parity · structured reflow + object-anchored annotations · Flutter + native ink ·
local-first event-sourced · iReal-импорт в v1 · бесплатно для базы тестеров.

### D8 — Riverpod как state management

Принято: Riverpod. Причина: code-gen, тестируемость без widget-дерева, отсутствие зависимости
от `BuildContext` в контроллерах.

### D9 — ADR не ведутся

Решение владельца проекта. Записи решений переносятся в раздел 9 этого документа. Причина:
церемония на каждое решение не окупается на текущем размере команды.

### D10 — `melos.yaml` заменён на секцию `melos:` в корневом `pubspec.yaml`

Вынужденное: Melos 8 не читает `melos.yaml` вообще. Пакеты обнаруживаются полем `workspace:`
(Dart pub workspaces), каждый участник объявляет `resolution: workspace`.

### D11 — версия Flutter пинована в `.fvmrc` (3.47.7 / Dart 3.13.5)

Причина: воспроизводимость golden-тестов и layout-бенчей. Локально SDK резолвится через
`sdkPath: .fvm/flutter_sdk`; CI ставит ту же версию и экспортирует `MELOS_SDK_PATH`.

### D12 — `test` пинован в 1.31.1

Вынужденное: `flutter_test` в Flutter 3.47.7 требует `test_api 0.7.12` **точно**, и только
`test 1.31.1` объявляет тот же пин. Дополнительно из-за этого `build_runner` пинован в 2.15.1:
версия 2.16.2 требует `analyzer ^14.3.0`, а `test 1.31.1` — `analyzer <14`. Пересматривать при
каждом обновлении Flutter.

### D13 — `storage_drift` без `sqlite3_flutter_libs`

Причина: пакет снят с развития — pub.dev отдаёт `0.6.0+eol` с описанием «Not used anymore,
update to version 3.x of package:sqlite3 instead», а `drift 2.35.2` уже зависит от `sqlite3
^3.4.0`, который собирает нативную библиотеку через Dart build hooks. `drift_flutter` всё ещё
тянет EOL-пакеты транзитивно, поэтому выбор opener-а отложен до спайка S5, который измеряет
cold-open против порога 1000 мс.

### D14 — desktop-таргеты (Windows и Linux) в `apps/mobile`

Причина: S4 требует отклика < 16 мс/страницу, и живой отклик на ПК ускоряет итерацию по layout
без эмулятора. Ограничение: `PlatformView`-ink на десктопе не работает; app-facing пакет
`ink_native` регистрирует no-op реализацию, а редактор читает `supportsInk` и не предлагает
ink-инструменты.

### D15 — модель аккорда: класс высоты + явное предпочтение написания + `SpellingTable`

Выбрано владельцем проекта из трёх вариантов. Корень аккорда хранит звучащую высоту
(`pitchClass`) и необязательное `SpellingPreference` (`automatic | sharp | flat`); письменная
форма не хранится, а **вычисляется** функцией `SpellingTable.spell(pitchClass, key, preference)`.

Причина, по которой это важно, а не косметика: написание — чистая функция от трёх входов,
поэтому круговой обход 12 ключей возвращает исходное написание **по построению**, а не по
совпадению. Если бы корень хранил букву и альтерацию и переписывался по буквенным шагам,
замкнутость зависела бы от истории преобразований. Альтернатива «только класс высоты» отброшена:
она теряет замысел композитора (bVI перестаёт быть bVI).

Отвергнуто: хранение написания в корне и диатоническое транспонирование по буквам — даёт
замкнутость, но один и тот же аккорд в разных контекстах пишется по-разному, а таблица не нужна.

### D16 — хроматические ноты в тональности без знаков пишутся с бемолями

Документированное упрощение. Правило: диатонические ступени берутся из знаков тональности (там
предпочтение не действует вообще); для остальных пяти классов высоты выбирается написание с
наименьшим числом знаков, затем — по направлению тональности (`fifths > 0` → диезы, иначе
бемоли). Тональность без знаков (C major, A minor) попадает в ветку бемолей.

Причина: единое направление не может быть верным для всех шести хроматических нот. В C major
традиция смешанная — bII, bIII, bV, bVI, bVII пишутся с бемолями, а #IV с диезом. Бемоли верны
для пяти из шести, диезы — для одного из шести. **Известное отклонение: #IV в C major даёт `Gb`
вместо `F#`**; это зафиксировано тестом `the tritone above the tonic is a documented deviation`,
чтобы изменение правила было осознанным решением, а не сюрпризом. Escape hatch — явное
`SpellingPreference` на аккорде. Полный учёт контекста требует гармонического анализа, которого в
проекте нет; догадка, одетая в правило, была бы заметно хуже записанного ограничения.

### D17 — `scaleOf` применяет минорный интервальный шаблон к минорным тональностям

Исправление бага, найденного спайком S3. Первая реализация применяла мажорный шаблон
`[0,2,4,5,7,9,11]` от любой тоники, поэтому для E minor возвращала ноты **параллельного мажора**
(E F# G# A B C# D#) вместо натурального минора (E F# G A B C D), и аккорд, принадлежащий
тональности, сверялся бы со шкалой, которой в этой тональности нет. Теперь шаблон выбирается по
`Mode`: `[0,2,4,5,7,9,11]` для мажора и `[0,2,3,5,7,8,10]` для минора.

Причина, по которой это стоит записи: баг не проявлялся ни на одной мажорной тональности, а
спайк S3 гоняет только мажорный цикл. Его поймал отдельный тест `scaleOf` на A minor и E minor.

### D18 — gate усилен: `public_member_api_docs` переведён в `warning`

Найдено при проверке, а не при написании. `dart analyze` возвращает **0**, когда видит только
замечания уровня `info`, а этот линт по умолчанию именно `info`. То есть требование
«документация — часть контракта» **не было ничем обеспечено**: анализ печатал «2 issues found» и
выходил с кодом 0, а `melos run verify` отчитывался SUCCESS.

Теперь правило объявлено `warning` в `analysis_options.yaml`, и gate падает. Проверено
фальсификацией: с внесённым нарушением `dart analyze` вернул 2, после удаления — 0.

`todo` намеренно оставлен `info`: TODO разрешены, но должны быть видимы, и валить из-за них
сборку не нужно.

### D19 — структура ча́рта: секция → такты, маркеры на тактах

Выбрано владельцем проекта из трёх вариантов (против иерархии `RepeatGroup`/`VoltaGroup` и
против плоского потока токенов). Секция содержит список тактов; каждый такт несёт **свою**
длину, размер, тактовые черты, номер вольты, маркер «повторить предыдущий такт/два», слэш-повтор,
метку N.C. и знаки (segno/coda/фермата/остановка игрока).

Причина: якорь аннотации адресуется как `{sectionId, bar, beat, step?}`. При плоском списке
тактов внутри секции адрес такта — это одно число. В иерархии тот же адрес стал бы путём из
нескольких индексов, и вставка одного такта переписывала бы структуру вокруг него, отвязывая все
аннотации. Размер хранится на такте, а не на песне, потому что в реальных ча́ртах он меняется
внутри песни: песенная константа заставила бы импортёр выдумать «значение по умолчанию» и затем
потерять каждое изменение.

`Volta(0)` — это **безымянная** скобка (`N0`), и это отличается от отсутствия скобки (`volta ==
null`). Поля-признака с тремя состояниями не заводится: `null` означает «нет скобки».

### D20 — хранится только написанная форма; порядок исполнения — производное

Выбрано владельцем проекта. `Song` не содержит развёрнутого порядка. Повторы, вольты и навигация
записаны в тактах, а развёртка — чистая функция над этим значением.

Причина: два представления одной музыки рано или поздно разойдутся на отредактированном ча́рте, и
не останется способа понять, какое из них читает музыкант. SDD требует и структуру (edit), и
порядок (Scene) — но требование иметь оба **представления** не означает хранить оба.

Следствие, зафиксированное как пробел: сама функция развёртки ещё не написана. Повторы, вольты и
размер уже смоделированы и покрыты тестами; навигация (`D.C. al Coda`, `D.S. al Fine`, кода,
фине) распознаётся только как сохраняемый дословно текст `<…>` на такте и будет интерпретирована
вместе с развёрткой. Причина отложить: разведка показала, что обработка навигации различается
между реализациями, а корпуса для проверки у нас нет.

### D21 — размерные маркеры `s`/`l` и повторы `x`/`r`/`p` смоделированы как состояние

По разведке iReal: `s` (мелкий шрифт) и `l` (обычный) — **состояние**, сохраняющееся между
тактами; `x` (повторить предыдущий такт), `r` (предыдущие два) и `p` (слэш-повтор предыдущего
аккорда) зависят от предшествующей музыки. Поэтому `ChordSize` хранится на каждом аккорде (а не
как флаг такта — иначе изменение внутри такта теряется), а `RepeatPrevious` и `slashRepeat` — на
такте, потому что они ссылаются на музыку, которой в этом такте нет.

---

## 10. Статус Phase 1

| Спайк | Вопрос | Статус |
|---|---|---|
| **S3** | Круговой обход 12 ключей сохраняет написание? | **PASS** — 204 образца (17 аккордов × 12 стартовых ключей), 0 расхождений; 5100 проверок «написание не меняет звучание», 0 расхождений. Запуск: `dart run bin/spike.dart s3` из `tools/spike_harness` |
| S1 | iReal: структура 100%, аккорды ≥ 99% | **ЗАБЛОКИРОВАН** — нужны реальные экспорты iReal от владельца |
| S4 | layout < 16 мс/страница | Не начат; модель песни готова (D19–D21), метрика не снята |
| S5 | cold-open < 1000 мс p95 | Не начат; ждёт выбора opener-а |

**Модель песни готова** и покрыта тестами: `Song` → `Section` → `Bar` → `BeatChord`, с размером,
вольтами, повторами, знаками и дословным текстом. Это фундамент, которого ждали и S1, и S4.

**Что модель НЕ содержит и почему это записано, а не забыто:** функции развёртки порядка
исполнения (повторы + вольты разворачиваются тривиально, навигация требует корпуса), самого
движка layout и кодеков.

**Важная поправка по S1, полученная разведкой формата.** Ходячее представление, что тело
`irealbook://` — это base64, **неверно**. Тело — percent-encoded UTF-8; поле музыки несёт
10-символьный магический префикс `1r34LbKcu7` (именно 10, не 9 — ошибка на единицу молча
портит все аккорды в правдоподобно выглядящий мусор) и проходит через фиксированную перестановку
блоками по 50 символов (`obfusc50`, инволюция) плюс три текстовые замены: `Kcl`→`| x`, `LZ`→` |`,
`XyQ`→три пробела. Порядок обязателен: сначала перестановка, потом замены. Экспорт приложения —
это HTML с одной ссылкой `irealb://`, где песни разделены `===`, а последний сегмент — имя
плейлиста, а не песня. Также: `[` `]` — это двойные тактовые черты, а **повторы** — `{` `}`;
круглые скобки — альтернативный аккорд, а не добавленная ступень.

Разведка подтверждена независимым round-trip на реальном экспорте и шестью реализациями-парсерами.
Две вещи в ней остаются невыясненными и должны быть проверены на ваших файлах: обход `obfusc50`
идёт по байтам или по символам для не-ASCII текста, и назначение поля 2 в 10-полевой раскладке.
