param(
    [ValidateSet('Ensure', 'Resolve')]
    [string]$Action = 'Ensure',
    [string]$Query = '',
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'
$SkillDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $SkillDirectory 'paths.ps1')

function Write-JsonResult([object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 8 -Compress
    if ($OutFile) {
        $fullOutFile = [IO.Path]::GetFullPath($OutFile)
        if (Test-Path -LiteralPath $fullOutFile) {
            throw 'OutFile must be a new path.'
        }
        [IO.File]::WriteAllText($fullOutFile, $json,
            (New-Object Text.UTF8Encoding($false)))
    }
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    [Console]::WriteLine($json)
}

if (-not $RootReady) {
    Write-JsonResult ([ordered]@{
        status = 'error'
        code = 'ROOT_NOT_READY'
        message = 'The confirmed Panlifang installation is not ready.'
    })
    exit 31
}

[IO.Directory]::CreateDirectory($UserDataDir) | Out-Null
$CachePath = Join-Path $UserDataDir 'instrument-catalog.json'
$Today = [DateTime]::Now.ToString('yyyy-MM-dd')
$Cache = $null
if (Test-Path -LiteralPath $CachePath) {
    try {
        $Cache = [IO.File]::ReadAllText($CachePath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
    } catch {
        $Cache = $null
    }
}

$NeedsRefresh = -not $Cache -or
    [string]$Cache.local_date -ne $Today -or
    [string]$Cache.root -ne $Root -or
    -not $Cache.instruments

if ($NeedsRefresh) {
    $OutputPath = Join-Path $UserDataDir ('instrument-list-' + [Guid]::NewGuid().ToString('N') + '.json')
    $response = $null
    try {
        $arguments = @('instrument-list') + $RootArgs + @('--out', $OutputPath)
        $cliStdout = & $Cli @arguments
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            throw 'plf-cli instrument-list did not create its JSON response.'
        }
        $response = [IO.File]::ReadAllText($OutputPath, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
        if (-not $response.success -or
            [string]$response.data.schema -ne 'plf-instrument-catalog/1' -or
            -not $response.data.instruments) {
            throw 'plf-cli returned an invalid instrument catalog.'
        }
        $Cache = [ordered]@{
            schema = 'plf-skill-instrument-cache/1'
            local_date = $Today
            fetched_at = [DateTimeOffset]::Now.ToString('o')
            root = $Root
            instruments = @($response.data.instruments)
        }
        $cacheJson = $Cache | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($CachePath, $cacheJson,
            (New-Object Text.UTF8Encoding($false)))
        $Cache = $cacheJson | ConvertFrom-Json
    } catch {
        if ($response -and [string]$response.error.code -eq 'PERMISSION_DENIED') {
            Write-JsonResult ([ordered]@{
                status = 'error'
                code = 'PERMISSION_DENIED'
                message = [string]$response.error.message
                retryable = $false
            })
            exit 32
        }
        Write-JsonResult ([ordered]@{
            status = 'error'
            code = 'INSTRUMENT_CATALOG_REFRESH_FAILED'
            message = $_.Exception.Message
        })
        exit 32
    } finally {
        if (Test-Path -LiteralPath $OutputPath) {
            [IO.File]::Delete($OutputPath)
        }
    }
}

if ($Action -eq 'Ensure') {
    Write-JsonResult ([ordered]@{
        status = 'ready'
        local_date = [string]$Cache.local_date
        fetched_at = [string]$Cache.fetched_at
        count = @($Cache.instruments).Count
        cache = $CachePath
    })
    exit 0
}

$Query = $Query.Trim()
if ($Query.Length -eq 0) {
    Write-JsonResult ([ordered]@{
        status = 'error'
        code = 'EMPTY_INSTRUMENT_QUERY'
        message = 'Resolve requires a non-empty query.'
    })
    exit 10
}

$Items = @($Cache.instruments)
$FutureItems = @($Items | Where-Object { [string]$_.asset_type -eq 'future' })
$StockItems = @($Items | Where-Object { [string]$_.asset_type -eq 'stock' })
$Seed = $null
$SeedPath = Join-Path $SkillDirectory 'references\contracts.seed.json'
try {
    $Seed = [IO.File]::ReadAllText($SeedPath, [Text.Encoding]::UTF8) |
        ConvertFrom-Json
} catch {
    $Seed = $null
}

function Find-Future([string]$Name, [object[]]$Futures, [object]$AliasSeed) {
    $hits = @($Futures | Where-Object {
        [string]$_.name -ieq $Name -or [string]$_.key -ieq $Name
    })
    if ($hits.Count -gt 0) { return $hits }
    if (-not $AliasSeed -or -not $AliasSeed.products) { return @() }

    $products = @($AliasSeed.products | Where-Object {
        [string]$_.code -ieq $Name -or
        @($_.names | Where-Object { [string]$_ -ieq $Name }).Count -gt 0
    })
    $resolved = @()
    foreach ($product in $products) {
        $baseKey = ([string]$product.ex + ' ' + [string]$product.code).Trim()
        $resolved += @($Futures | Where-Object { [string]$_.key -ieq $baseKey })
    }
    return @($resolved | Sort-Object -Property key -Unique)
}

function Write-FutureChoices([string]$InputQuery, [object]$Future) {
    $baseKey = [string]$Future.key
    $monthFormat = if ($baseKey.StartsWith('ZCE ', [StringComparison]::OrdinalIgnoreCase)) {
        '3_or_4_digits'
    } else {
        '4_digits'
    }
    Write-JsonResult ([ordered]@{
        status = 'need_contract'
        code = 'FUTURE_CONTRACT_REQUIRED'
        query = $InputQuery
        asset_type = 'future'
        name = [string]$Future.name
        base_key = $baseKey
        candidates = @(
            [ordered]@{ name = [string]$Future.name + $IndexSuffix; key = ($baseKey + ' IDX') },
            [ordered]@{ name = [string]$Future.name + $MainContinuousSuffix; key = ($baseKey + ' MI') }
        )
        month_format = $monthFormat
    })
}

$IndexSuffix = -join @([char]0x6307, [char]0x6570)
$MainContinuousSuffix = -join @([char]0x4E3B, [char]0x8FDE)
$MainForceSuffix = -join @([char]0x4E3B, [char]0x529B)
$ContinuousSuffix = -join @([char]0x8FDE, [char]0x7EED)

# A complete stock ContractID is the only accepted direct stock key.
$ExactStockKey = @($StockItems | Where-Object { [string]$_.key -ieq $Query })
if ($ExactStockKey.Count -eq 1) {
    Write-JsonResult ([ordered]@{
        status = 'resolved'; query = $Query; asset_type = 'stock'
        name = [string]$ExactStockKey[0].name; key = [string]$ExactStockKey[0].key
    })
    exit 0
}

$ExactStockName = @($StockItems | Where-Object { [string]$_.name -eq $Query })
if ($ExactStockName.Count -eq 1) {
    Write-JsonResult ([ordered]@{
        status = 'resolved'; query = $Query; asset_type = 'stock'
        name = [string]$ExactStockName[0].name; key = [string]$ExactStockName[0].key
    })
    exit 0
}

# Validate or normalize an already complete three-part future key.
$KeyParts = @($Query -split '\s+' | Where-Object { $_ })
if ($KeyParts.Count -eq 3) {
    $BaseKey = $KeyParts[0].ToUpperInvariant() + ' ' + $KeyParts[1].ToUpperInvariant()
    $KeyFuture = @(Find-Future $BaseKey $FutureItems $Seed)
    if ($KeyFuture.Count -eq 1) {
        $Third = $KeyParts[2].ToUpperInvariant()
        if ($Third -eq 'IDX' -or $Third -eq 'MI') {
            Write-JsonResult ([ordered]@{
                status = 'resolved'; query = $Query; asset_type = 'future'
                name = [string]$KeyFuture[0].name; key = ($BaseKey + ' ' + $Third)
            })
            exit 0
        }
        if ($Third -match '^[0-9]{3,4}$') {
            if ($BaseKey.StartsWith('ZCE ', [StringComparison]::OrdinalIgnoreCase)) {
                if ($Third.Length -eq 4) { $Third = $Third.Substring(1) }
                if ($Third.Length -ne 3) { $Third = '' }
            } elseif ($Third.Length -ne 4) {
                $Third = ''
            }
            if ($Third) {
                Write-JsonResult ([ordered]@{
                    status = 'resolved'; query = $Query; asset_type = 'future'
                    name = [string]$KeyFuture[0].name; key = ($BaseKey + ' ' + $Third)
                })
                exit 0
            }
        }
    }
}

$Leg = ''
$BaseName = $Query
$LegWords = @(
    [pscustomobject]@{ Text = $IndexSuffix; Code = 'IDX' },
    [pscustomobject]@{ Text = $MainContinuousSuffix; Code = 'MI' },
    [pscustomobject]@{ Text = $MainForceSuffix; Code = 'MI' },
    [pscustomobject]@{ Text = $ContinuousSuffix; Code = 'MI' }
)
if ($Seed -and $Seed.legWords) {
    foreach ($word in @($Seed.legWords.IDX)) {
        $LegWords += [pscustomobject]@{ Text = [string]$word; Code = 'IDX' }
    }
    foreach ($word in @($Seed.legWords.MI)) {
        $LegWords += [pscustomobject]@{ Text = [string]$word; Code = 'MI' }
    }
}
$LegWords = @($LegWords | Group-Object -Property Text | ForEach-Object { $_.Group[0] } |
    Sort-Object @{ Expression = { $_.Text.Length }; Descending = $true })
foreach ($candidate in $LegWords) {
    if ($Query.EndsWith($candidate.Text, [StringComparison]::Ordinal)) {
        $Leg = $candidate.Code
        $BaseName = $Query.Substring(0, $Query.Length - $candidate.Text.Length).Trim()
        break
    }
}

if ($Leg) {
    $Futures = @(Find-Future $BaseName $FutureItems $Seed)
    if ($Futures.Count -eq 1) {
        Write-JsonResult ([ordered]@{
            status = 'resolved'; query = $Query; asset_type = 'future'
            name = [string]$Futures[0].name; key = ([string]$Futures[0].key + ' ' + $Leg)
        })
        exit 0
    }
}

# Natural-language dated futures require an explicit four-digit year/month.
$MonthMatch = [regex]::Match($Query, '^(?<name>.+?)\s*(?<month>[0-9]{4})$')
if ($MonthMatch.Success) {
    $BaseName = $MonthMatch.Groups['name'].Value.Trim()
    $MonthCode = $MonthMatch.Groups['month'].Value
    $Futures = @(Find-Future $BaseName $FutureItems $Seed)
    if ($Futures.Count -eq 1) {
        $BaseKey = [string]$Futures[0].key
        $ContractCode = if ($BaseKey.StartsWith('ZCE ', [StringComparison]::OrdinalIgnoreCase)) {
            $MonthCode.Substring(1)
        } else {
            $MonthCode
        }
        Write-JsonResult ([ordered]@{
            status = 'resolved'; query = $Query; asset_type = 'future'
            name = [string]$Futures[0].name; key = ($BaseKey + ' ' + $ContractCode)
        })
        exit 0
    }
}

$ShortMonthMatch = [regex]::Match($Query, '^(?<name>.+?)\s*(?<month>[0-9]{2,3})$')
if ($ShortMonthMatch.Success) {
    $ShortBaseName = $ShortMonthMatch.Groups['name'].Value.Trim()
    $ShortMonthCode = $ShortMonthMatch.Groups['month'].Value
    $ShortFutures = @(Find-Future $ShortBaseName $FutureItems $Seed)
    if ($ShortFutures.Count -eq 1) {
        $ShortBaseKey = [string]$ShortFutures[0].key
        if ($ShortMonthCode.Length -eq 3 -and
            $ShortBaseKey.StartsWith('ZCE ', [StringComparison]::OrdinalIgnoreCase)) {
            Write-JsonResult ([ordered]@{
                status = 'resolved'; query = $Query; asset_type = 'future'
                name = [string]$ShortFutures[0].name
                key = ($ShortBaseKey + ' ' + $ShortMonthCode)
            })
            exit 0
        }
        Write-JsonResult ([ordered]@{
            status = 'not_found'
            code = 'INVALID_MONTH_FORMAT'
            query = $Query
            candidates = @()
        })
        exit 3
    }
}

$ExactFuture = @(Find-Future $Query $FutureItems $Seed)
if ($ExactFuture.Count -eq 1) {
    Write-FutureChoices $Query $ExactFuture[0]
    exit 2
}

$Candidates = @($Items | Where-Object {
    ([string]$_.name).IndexOf($BaseName, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $BaseName.IndexOf([string]$_.name, [StringComparison]::OrdinalIgnoreCase) -ge 0
} | Select-Object -First 10 | ForEach-Object {
    [ordered]@{ asset_type = [string]$_.asset_type; name = [string]$_.name; key = [string]$_.key }
})

Write-JsonResult ([ordered]@{
    status = $(if ($ExactStockName.Count -gt 1 -or $ExactFuture.Count -gt 1 -or $Candidates.Count -gt 0) { 'ambiguous' } else { 'not_found' })
    query = $Query
    candidates = $Candidates
})
exit $(if ($Candidates.Count -gt 0) { 2 } else { 3 })
