# Агент «Archer & FPS Optimizer» — как подключить

Три файла:

| файл | что это |
|---|---|
| `agents/archer_fps_optimizer/SYSTEM_PROMPT.md` | системная инструкция агента (роль, правила, обязательный отчёт) |
| `.claude/agents/archer-fps-optimizer.md` | описание суб-агента для Claude Code (frontmatter `name/description/tools` + короткая инструкция, которая отсылает к SYSTEM_PROMPT.md) |
| `qa_archer_bench/Test.gd` (+ `Test.tscn`) | бенчмарк лучников: 120 стрелков, два режима стрельбы («по готовности» и «залп»), физтик, кадр, FPS, вердикты |

## Шаг 1. Claude Code

Файл `.claude/agents/archer-fps-optimizer.md` уже лежит в проекте — Claude Code
подхватывает его сам. Проверить: `/agents` в терминале Claude Code покажет
`archer-fps-optimizer`. Позвать:

```
Используй субагента archer-fps-optimizer: прогони qa_archer_bench в окне и
headless, найди самую дорогую ветку у лучников и предложи правку с A/B.
```

или адресно: `@archer-fps-optimizer …`. Агент читает `SYSTEM_PROMPT.md` первым
делом и заканчивает работу отчётом по шаблону из него.

## Шаг 2. Cursor / VS Code (Copilot Chat, Continue, любой ассистент с системным промптом)

1. Скопируйте содержимое `agents/archer_fps_optimizer/SYSTEM_PROMPT.md` в
   **Custom Instructions / System Prompt / Rules** ассистента (в Cursor —
   `Settings → Rules for AI`, или положите файл как `.cursor/rules/archer-fps-optimizer.mdc`
   с заголовком `alwaysApply: false` и вызывайте `@archer-fps-optimizer`).
2. Добавьте в контекст беседы `CLAUDE.md` (карта проекта) — агент опирается на
   его разделы про лучников, залп, навигацию и правила производительности.
3. Первым сообщением попросите замер: «прогони `qa_archer_bench` и покажи таблицу».

## Шаг 3. Запуск бенчмарка руками

```powershell
$G = "E:\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
cd E:\Games\ten_thousand_spearmen\ten_thousand_spearmen
# headless — честны физтик и счётчики (FPS в headless не показателен)
& $G --headless --path . res://qa_archer_bench/Test.tscn
# окно — FPS и интервал кадра
& $G --path . res://qa_archer_bench/Test.tscn
# параметры: число лучников, размер отряда, дистанция до цели, секунд на режим
& $G --headless --path . res://qa_archer_bench/Test.tscn -- archers=200 squad=40 dist=18 secs=30
```

Отчёт печатается одной таблицей: режим · выстрелов · пик за 0,1 с · стрел в
воздухе (пик) · физтик мс · кадр логики мс · интервал кадра (средний / p95 /
худший) · FPS. Вердикты — свойства: залп даёт пачки (V1), «по готовности» —
нет (V2), оба режима стреляют (V3), стрелы из пула (V4). Итог — строкой
«провалов: N»; в сводке шлюза считать и `SCRIPT ERROR`.

Порядок режимов в бенчмарке намеренно «по готовности → залп»: залп
синхронизирует перезарядки всего отряда, и после него стрелки стреляли бы
пачками ещё минуту — в обратном порядке второй режим мерил бы хвост первого.
