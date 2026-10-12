# Panlifang installation root for THIS skill copy.
#
# Layout: everything shared and read-only stays in the skill root; everything
# that is PRIVATE TO THIS COPY lives under usr\ :
#   usr\root.local.json   - the confirmed Panlifang install root
#   usr\work-formulas\    - formulas this copy generated
#
# Active root resolution order:
#   1. usr\root.local.json, written by scripts\plf-root.ps1 when the user
#      confirms a root (first launch).
#   2. $FallbackRoot below, used only until a root has been confirmed.
#
# One root per copy. Never copy usr\ between skill copies and never hand-edit
# it. Edit $FallbackRoot only when this copy's default guess is wrong.
# $CliFound is the ONLY signal for "is Panlifang here" - never scan for it.

$FallbackRoot = [IO.Path]::GetFullPath('C:\Ejia7\EjiaCube'.TrimEnd('\'))

$SkillRoot = [IO.Path]::GetFullPath($PSScriptRoot.TrimEnd('\'))
$UserDataDir = Join-Path $SkillRoot 'usr'
$RootStateFile = Join-Path $UserDataDir 'root.local.json'
$RootHelper = Join-Path $SkillRoot 'scripts\plf-root.ps1'

# --- Resolve $Root -----------------------------------------------------------
$Root = $FallbackRoot
$RootSource = 'fallback'
$RootConfirmed = $false
$RootState = $null

if (Test-Path -LiteralPath $RootStateFile) {
    try {
        $RootState = [IO.File]::ReadAllText(
            $RootStateFile, [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
    } catch {
        $RootState = $null
    }
}

if ($RootState -and $RootState.root) {
    $StatedRoot = ([string]$RootState.root).Trim().TrimEnd('\')
    if ($StatedRoot.Length -gt 0) {
        $Root = [IO.Path]::GetFullPath($StatedRoot)
        $RootSource = 'usr\root.local.json'
        $RootConfirmed = [bool]$RootState.confirmed
    }
}

# --- Derived CLI path -------------------------------------------------------
$CliCandidates = @(
    (Join-Path $Root 'plf-cli.exe'),
    (Join-Path $Root 'Debug\plf-cli.exe'),
    (Join-Path $Root 'Release\plf-cli.exe')
)
$Cli = $CliCandidates | Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
$CliFound = [bool]$Cli
if (-not $CliFound) {
    $Cli = $CliCandidates[0]
}

# --- Root gate --------------------------------------------------------------
# Compile only when the root was confirmed by the user and still resolves a
# real Panlifang install (plf-cli.exe present). Otherwise SKILL.md must run the
# first-launch root setup: state the default path, and if Panlifang is absent
# from it, ask the user for the install directory instead of searching.
$RootReady = ($RootConfirmed -and $CliFound)

# Insert into every CLI argument array right after the subcommand:
#   $CliArguments = @('status') + $RootArgs + @('--out', $Output)
$RootArgs = @('--root', $Root)

# --- Fixed skill paths ------------------------------------------------------
$WorkDir = Join-Path $UserDataDir 'work-formulas'
$FormulaFunctions = Join-Path $SkillRoot 'references\formula-functions.md'
$CliCommands = Join-Path $SkillRoot 'references\cli-commands.md'
$RootConfig = Join-Path $SkillRoot 'references\root-config.md'
$SuccessTemplate = Join-Path $SkillRoot 'assets\agent-demo.md'
$InvalidTemplate = Join-Path $SkillRoot 'assets\invalid-formula.md'
