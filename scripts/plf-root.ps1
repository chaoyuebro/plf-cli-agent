# plf-root.ps1 - resolve, persist and verify the Panlifang installation root
# for THIS skill copy.
#
# ASCII only by design: PowerShell 5.1 parses a BOM-less .ps1 with the system
# ANSI code page, so non-ASCII literals here would be corrupted before running.
#
# Usage (always pass a fresh -OutFile and read that JSON back):
#   plf-root.ps1 -Action info  [-OutFile <new.json>]
#   plf-root.ps1 -Action discover [-OutFile <new.json>]
#   plf-root.ps1 -Action set -RootPath <dir> [-ResolvedFrom user] [-OutFile <new.json>]
#   plf-root.ps1 -Action verify [-OutFile <new.json>]
#   plf-root.ps1 -Action reset [-OutFile <new.json>]
#
# Discovery is read-only: inspect running clients and registry hints, then search
# accessible fixed local drives for EJClient.exe if no installation was found.
# It never runs a discovered executable or writes this copy's private state.

[CmdletBinding()]
param(
    [ValidateSet('info', 'discover', 'set', 'verify', 'reset')]
    [string]$Action = 'info',
    [string]$RootPath,
    [string]$ResolvedFrom = 'user',
    [string]$OutFile,
    [switch]$Quiet,
    [string[]]$SearchRoots,
    [ValidateRange(1,600)][int]$SearchTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$Schema = 'plf-root/1'

# Kept separate: paths.ps1 (dot-sourced below) overwrites $Root.
$TargetRoot = $RootPath

$ScriptDir = $PSScriptRoot
$SkillRoot = [IO.Path]::GetFullPath((Split-Path -Parent $ScriptDir).TrimEnd('\'))
$PathsFile = Join-Path $SkillRoot 'paths.ps1'
$UserDataDir = Join-Path $SkillRoot 'usr'
$StateFile = Join-Path $UserDataDir 'root.local.json'

function Write-Result {
    param($Payload)
    $json = $Payload | ConvertTo-Json -Depth 6 -Compress
    if ($OutFile) {
        $OutDir = Split-Path -Parent $OutFile
        if ($OutDir -and -not (Test-Path -LiteralPath $OutDir)) {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        }
        [IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding($false)))
    }
    if (-not $Quiet) { Write-Output $json }
    exit 0
}

function Write-Failure {
    param([string]$Code, [string]$Message, $Extra)
    $payload = [ordered]@{
        schema     = $Schema
        action     = $Action
        ok         = $false
        skill_root = $SkillRoot
        state_file = $StateFile
        error      = [ordered]@{ code = $Code; message = $Message }
    }
    if ($Extra) {
        foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
    }
    Write-Result $payload
}

function Resolve-RootPath {
    param([string]$Dir)
    if (-not $Dir) { return $null }
    $trimmed = $Dir.Trim().Trim('"')
    if ($trimmed.Length -eq 0) { return $null }
    try {
        $absolute = [IO.Path]::GetFullPath($trimmed)
        if ($absolute -eq [IO.Path]::GetPathRoot($absolute)) { return $absolute }
        return $absolute.TrimEnd('\')
    } catch { return $null }
}

function Get-PlfCliPath {
    param([string]$Dir)
    if (-not $Dir) { return $null }
    foreach ($candidate in @(
            (Join-Path $Dir 'plf-cli.exe'),
            (Join-Path $Dir 'Debug\plf-cli.exe'),
            (Join-Path $Dir 'Release\plf-cli.exe')
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $PathsFile)) {
    Write-Failure -Code 'PATHS_FILE_MISSING' -Message "paths.ps1 not found: $PathsFile"
}

# Defines $FallbackRoot, $Root, $RootSource, $RootConfirmed, $RootStateFile,
# $RootHelper, $Cli, $CliFound, $RootReady, $RootArgs and the skill paths.
. $PathsFile

if ($Action -eq 'discover') {
    $found = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $runningRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $scanTimer = [Diagnostics.Stopwatch]::StartNew()
    $scanTimedOut = $false
    $unreadable = 0
    function Add-InstallationCandidate([string]$Directory, [string]$Source) {
        $candidateRoot = Resolve-RootPath $Directory
        if (!$candidateRoot) { return }
        if (![IO.File]::Exists((Join-Path $candidateRoot 'EJClient.exe'))) { return }
        if (!$found.ContainsKey($candidateRoot)) {
            $found.Add($candidateRoot, [pscustomobject]@{
                root=$candidateRoot; cli=(Get-PlfCliPath $candidateRoot)
                has_exe=$true; source=$Source; running=$runningRoots.Contains($candidateRoot)
            })
        } elseif ($runningRoots.Contains($candidateRoot)) {
            $found[$candidateRoot].running=$true
        }
    }
    # Explicit roots are useful for deterministic tests; they disable machine-wide hints.
    if (!$SearchRoots -or $SearchRoots.Count -eq 0) {
        foreach ($clientProcess in @(Get-Process -Name EJClient -ErrorAction SilentlyContinue)) {
            try {
                $clientExe = $clientProcess.Path
                if ($clientExe) {
                    $clientDirectory = Split-Path -Parent $clientExe
                    [void]$runningRoots.Add($clientDirectory)
                    Add-InstallationCandidate $clientDirectory 'running-client'
                }
            } catch { }
        }
        foreach ($hint in @($FallbackRoot, (Join-Path $env:ProgramFiles 'Ejia7\EjiaCube'),
            (Join-Path $env:LOCALAPPDATA 'Ejia7\EjiaCube'))) {
            Add-InstallationCandidate $hint 'common-location'
        }
        foreach ($registryBase in @('HKCU:\Software\Microsoft\Windows\CurrentVersion',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion')) {
            $appPath = Join-Path $registryBase 'App Paths\EJClient.exe'
            try {
                $key = Get-Item -LiteralPath $appPath -ErrorAction Stop
                $exeHint = [string]$key.GetValue('')
                if ($exeHint) { Add-InstallationCandidate (Split-Path -Parent $exeHint.Trim('"')) 'registry-app-path' }
            } catch { }
            foreach ($entry in @(Get-ItemProperty -Path (Join-Path $registryBase 'Uninstall\*') -ErrorAction SilentlyContinue)) {
                if ($entry.InstallLocation) { Add-InstallationCandidate ([string]$entry.InstallLocation) 'registry-uninstall' }
            }
        }
        $SearchRoots = @([IO.DriveInfo]::GetDrives() | Where-Object {
            $_.IsReady -and $_.DriveType -eq [IO.DriveType]::Fixed
        } | ForEach-Object { $_.RootDirectory.FullName })
    }
    # Enumerate directory names only. Skip junctions, network/removable drives and
    # protected OS trees; no strategy, account, history or user documents are read.
    $didFileSearch = $found.Count -eq 0
    if ($didFileSearch) {
        $queue = [Collections.Generic.Queue[string]]::new()
        $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($searchDirectory in $SearchRoots) {
            $absolute = Resolve-RootPath $searchDirectory
            if ($absolute -and [IO.Directory]::Exists($absolute)) { $queue.Enqueue($absolute) }
        }
        while ($queue.Count -gt 0) {
            if ($scanTimer.Elapsed.TotalSeconds -ge $SearchTimeoutSeconds) { $scanTimedOut=$true; break }
            $directory = $queue.Dequeue()
            if (!$visited.Add($directory)) { continue }
            Add-InstallationCandidate $directory 'local-disk'
            try { $children = [IO.Directory]::GetDirectories($directory) }
            catch { ++$unreadable; continue }
            foreach ($child in $children) {
                try {
                    $attributes=[IO.File]::GetAttributes($child)
                    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    $leaf=[IO.Path]::GetFileName($child)
                    if ($leaf -in @('Windows', '$Recycle.Bin', 'System Volume Information')) { continue }
                    $queue.Enqueue($child)
                } catch { ++$unreadable }
            }
        }
    }
    $candidates = @($found.Values | Sort-Object root)
    $usable = @($candidates | Where-Object { $_.cli })
    $active = @($usable | Where-Object { $_.running })
    $selectedRoot = $null
    if ($usable.Count -eq 1) { $selectedRoot=$usable[0].root }
    elseif ($active.Count -eq 1) { $selectedRoot=$active[0].root }
    Write-Result ([ordered]@{
        schema=$Schema; action='discover'; ok=$true; found=($candidates.Count -gt 0)
        candidates=$candidates; selected_root=$selectedRoot
        requires_selection=($usable.Count -gt 1 -and !$selectedRoot)
        file_search_performed=$didFileSearch; timed_out=$scanTimedOut
        unreadable_directory_count=$unreadable; skill_root=$SkillRoot
    })
}

if ($Action -eq 'info') {
    # Reports the default directory and whether it already carries Panlifang.
    # The separate discover action performs read-only installation discovery.
    Write-Result ([ordered]@{
            schema       = $Schema
            action       = 'info'
            ok           = $true
            skill_root   = $SkillRoot
            user_data    = $UserDataDir
            work_dir     = $WorkDir
            state_file   = $StateFile
            state_exists = (Test-Path -LiteralPath $StateFile)
            confirmed    = [bool]$RootConfirmed
            default_root = $FallbackRoot
            root         = $Root
            root_source  = $RootSource
            cli          = $Cli
            cli_found    = [bool]$CliFound
            has_exe      = (Test-Path -LiteralPath (Join-Path $Root 'EJClient.exe'))
            root_ready   = [bool]$RootReady
        })
}

if ($Action -eq 'set') {
    $normalized = Resolve-RootPath $TargetRoot
    if (-not $normalized) {
        Write-Failure -Code 'ROOT_NOT_GIVEN' -Message '-RootPath is empty or not a valid path.'
    }
    if (-not (Test-Path -LiteralPath $normalized -PathType Container)) {
        Write-Failure -Code 'ROOT_MISSING' -Message "Directory does not exist: $normalized" `
            -Extra ([ordered]@{ root = $normalized })
    }
    $cliPath = Get-PlfCliPath $normalized
    $hasExe = [IO.File]::Exists((Join-Path $normalized 'EJClient.exe'))
    if (-not $cliPath -or -not $hasExe) {
        Write-Failure -Code 'ROOT_INVALID' `
            -Message "Expected EJClient.exe in $normalized and plf-cli.exe in that directory or its Debug/Release subdirectory." `
            -Extra ([ordered]@{ root = $normalized })
    }

    if (-not (Test-Path -LiteralPath $UserDataDir)) {
        New-Item -ItemType Directory -Path $UserDataDir -Force | Out-Null
    }
    $state = [ordered]@{
        schema        = $Schema
        root          = $normalized
        cli           = $cliPath
        has_exe       = $hasExe
        resolved_from = $ResolvedFrom
        confirmed     = $true
        confirmed_at  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        skill_root    = $SkillRoot
    }
    [IO.File]::WriteAllText(
        $StateFile,
        ($state | ConvertTo-Json -Depth 4),
        (New-Object Text.UTF8Encoding($false))
    )

    Write-Result ([ordered]@{
            schema     = $Schema
            action     = 'set'
            ok         = $true
            root       = $normalized
            cli        = $cliPath
            has_exe    = $hasExe
            state_file = $StateFile
            state      = $state
        })
}

if ($Action -eq 'verify') {
    $outPath = Join-Path $env:TEMP ('plf-root-verify-' + [guid]::NewGuid().ToString('N') + '.json')
    $parsed = $null
    $failure = $null
    try {
        $cliArgs = @('status') + $RootArgs + @('--out', $outPath)
        & $Cli @cliArgs
        if (-not (Test-Path -LiteralPath $outPath)) {
            $failure = 'plf-cli did not create the --out JSON file.'
        } else {
            $parsed = Get-Content -Raw -Encoding UTF8 $outPath | ConvertFrom-Json
        }
    } catch {
        $failure = 'CLI_INVOKE_FAILED: ' + $_.Exception.Message
    } finally {
        if ([IO.File]::Exists($outPath)) { [IO.File]::Delete($outPath) }
    }

    if (-not $parsed) {
        Write-Failure -Code 'CLI_NO_RESPONSE' -Message ([string]$failure) `
            -Extra ([ordered]@{ root = $Root; cli = $Cli })
    }

    $installRoot = $null
    if ($parsed.data -and $parsed.data.install_root) {
        $installRoot = [string]$parsed.data.install_root
    }
    $identityOk = $false
    if ($installRoot) {
        $resolvedInstall = Resolve-RootPath $installRoot
        if ($resolvedInstall) {
            $identityOk = ($resolvedInstall.ToLowerInvariant() -eq $Root.ToLowerInvariant())
        }
    }

    $errorCode = $null
    if ($parsed.error -and $parsed.error.code) { $errorCode = [string]$parsed.error.code }
    $errorMessage = $null
    if ($parsed.error -and $parsed.error.message) { $errorMessage = [string]$parsed.error.message }

    Write-Result ([ordered]@{
            schema        = $Schema
            action        = 'verify'
            ok            = [bool]$parsed.success
            success       = [bool]$parsed.success
            exit_code     = $parsed.exit_code
            root          = $Root
            cli           = $Cli
            install_root  = $installRoot
            identity_ok   = $identityOk
            selected_pid  = $parsed.data.selected_pid
            ready         = $parsed.data.ready
            qdc_connected = $parsed.data.qdc_connected
            error_code    = $errorCode
            error_message = $errorMessage
        })
}

if ($Action -eq 'reset') {
    $existed = Test-Path -LiteralPath $StateFile
    if ($existed) { [IO.File]::Delete($StateFile) }
    Write-Result ([ordered]@{
            schema        = $Schema
            action        = 'reset'
            ok            = $true
            deleted       = $existed
            state_file    = $StateFile
            fallback_root = $FallbackRoot
        })
}
