<#
.SYNOPSIS
  Baja el entorno de la demo. Con -Borrar, además se lleva sus datos.

.DESCRIPTION
  Sin -Borrar, la base queda guardada en Docker y la próxima vez que corras
  levantar.ps1 arranca con todo lo que había (incluido lo que hiciste en un
  ensayo). Con -Borrar arranca de cero: escenario nuevo y tu cuenta copiada
  otra vez desde la instantánea.

  Las ventanas del panel, las funciones y el túnel se cierran a mano.
#>
param([switch]$Borrar)

$Raiz = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Work = Join-Path $Raiz '.demo'
if (-not (Test-Path (Join-Path $Work 'supabase\config.toml'))) {
  Write-Host 'No hay entorno de demo en esta máquina.'
  exit 0
}
if ($Borrar) {
  supabase stop --workdir $Work --no-backup
} else {
  supabase stop --workdir $Work
}
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process
Write-Host 'Demo abajo. Cerrá las ventanas "Ceres demo · panel" y "Ceres demo · funciones".'
