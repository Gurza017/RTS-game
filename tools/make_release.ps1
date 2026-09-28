# ═══════════════════════════════════════════════════════════════════════════
# СБОРКА РАЗДАЧИ: .exe + data_* В ОДНОЙ ПАПКЕ
# ═══════════════════════════════════════════════════════════════════════════
# Скопируешь из экспорта один .exe — игра не стартует вовсе
# (".NET assemblies not found": без data_* нет managed-сборок).
# Поэтому раздача — это ДВЕ вещи рядом, и состав проверяется, а не
# подразумевается.
#
# 23.09.2026: голосовое управление удалено из проекта целиком, вместе с ним
# из раздачи ушли libvosk и папка voice_models (88 МБ).
#
# Запуск (из корня проекта):
#   powershell -File tools/make_release.ps1 -Exe "E:\Games\Alfa 1.4.exe"
# Необязательно: -Out <папка раздачи> (по умолчанию <имя exe>_release рядом)
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
$exeItem = Get-Item -LiteralPath $Exe
$exeDir = $exeItem.DirectoryName
$base = [System.IO.Path]::GetFileNameWithoutExtension($exeItem.Name)
if ($Out -eq "") { $Out = Join-Path $exeDir ($base + "_release") }

# Папка данных экспорта зовётся по ИМЕНИ ПРОЕКТА, а не по имени .exe
$data = Get-ChildItem -LiteralPath $exeDir -Directory -Filter "data_*" | Select-Object -First 1
if ($null -eq $data) { throw "Ryadom s $Exe net papki data_* - sperva sdelay eksport iz redaktora" }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
Copy-Item -LiteralPath $exeItem.FullName -Destination $Out -Force
$pck = Join-Path $exeDir ($base + ".pck")
if (Test-Path -LiteralPath $pck) { Copy-Item -LiteralPath $pck -Destination $Out -Force }
Copy-Item -LiteralPath $data.FullName -Destination $Out -Recurse -Force

# Проверяем СОСТАВ, а не факт копирования
$need = @(
    (Join-Path $Out $exeItem.Name),
    (Join-Path $Out $data.Name)
)
foreach ($n in $need) {
    if (-not (Test-Path -LiteralPath $n)) { throw "V razdache ne hvataet: $n" }
}
Write-Host "Razdacha sobrana: $Out"
Write-Host "  exe + $($data.Name)"
