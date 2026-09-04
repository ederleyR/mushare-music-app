$ErrorActionPreference = 'Stop'

$applicationPath = Join-Path $PSScriptRoot 'mushare.exe'
if (-not (Test-Path $applicationPath)) {
    Write-Error 'No se encontro mushare.exe. Ejecuta este script dentro de la carpeta extraida de MuShare.'
    exit 1
}

$desktopPath = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath 'MuShare.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $applicationPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = "$applicationPath,0"
$shortcut.Save()

Write-Host "Acceso directo creado en: $shortcutPath"
Read-Host 'Presiona Enter para cerrar'