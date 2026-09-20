# ═══════════════════════════════════════════════════════════════════════════
# СБОРКА РАЗДАЧИ: .exe + data_* + voice_models В ОДНОЙ ПАПКЕ
# ═══════════════════════════════════════════════════════════════════════════
# Голосовое управление живёт НЕ в pck: нативной libvosk нужен настоящий путь
# на диске, поэтому модель Vosk (88 МБ) обязана лежать отдельной папкой рядом
# с .exe. Скопируешь из экспорта один .exe — игра либо не стартует вовсе
# (".NET assemblies not found": без data_* нет ни managed-сборок, ни libvosk),
# либо стартует немой: под иконкой V будет "V - нет модели".
#
# Запуск (из корня проекта):
#   powershell -File tools/make_release.ps1 -Exe "E:\Games\Alfa 1.4.exe"
# Необязательно: -Out <папка раздачи> (по умолчанию <имя exe>_release рядом)
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$exeItem = Get-Item -LiteralPath $Exe
$exeDir = $exeItem.DirectoryName
$base = [System.IO.Path]::GetFileNameWithoutExtension($exeItem.Name)
if ($Out -eq "") { $Out = Join-Path $exeDir ($base + "_release") }

# Папка данных экспорта зовётся по ИМЕНИ ПРОЕКТА, а не по имени .exe
$data = Get-ChildItem -LiteralPath $exeDir -Directory -Filter "data_*" | Select-Object -First 1
if ($null -eq $data) { throw "Ryadom s $Exe net papki data_* - sperva sdelay eksport iz redaktora" }

$model = Join-Path $proj "voice_models"
if (-not (Test-Path -LiteralPath $model)) { throw "Net $model - skachay model, sm. voice_models/README.md" }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
Copy-Item -LiteralPath $exeItem.FullName -Destination $Out -Force
$pck = Join-Path $exeDir ($base + ".pck")
if (Test-Path -LiteralPath $pck) { Copy-Item -LiteralPath $pck -Destination $Out -Force }
Copy-Item -LiteralPath $data.FullName -Destination $Out -Recurse -Force
Copy-Item -LiteralPath $model -Destination $Out -Recurse -Force

# Проверяем СОСТАВ, а не факт копирования: молчаливая раздача без libvosk или
# без модели - это ровно тот баг, ради которого скрипт и заведён
$need = @(
    (Join-Path $Out $exeItem.Name),
    (Join-Path (Join-Path $Out $data.Name) "libvosk.dll"),
    (Join-Path (Join-Path $Out "voice_models") "vosk-model-small-ru-0.22")
)
foreach ($n in $need) {
    if (-not (Test-Path -LiteralPath $n)) { throw "V razdache ne hvataet: $n" }
}
Write-Host "Razdacha sobrana: $Out"
Write-Host "  exe + $($data.Name) + voice_models (golos rabotaet)"
