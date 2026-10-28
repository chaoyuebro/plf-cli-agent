param(
    [ValidateSet('Ensure', 'Resolve')]
    [string]$Action = 'Ensure',
    [string]$Query = '',
    [string]$OutFile = '',
    [ValidateSet('', 'option')][string]$AssetType = '',
    [string]$Exchange = '',
    [string]$Commodity = '',
    [string]$Month = '',
    [ValidateSet('', 'C', 'P')][string]$CallPut = '',
    [string]$StrikePrice = '',
    [ValidateRange(0, 2147483647)][int]$ClientPid = 0
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

# Option discovery is on demand and never enters the daily future/stock cache.
function Invoke-OptionCli([object[]]$Arguments) {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('plf-option-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        $stdout = & $Cli @Arguments --out $temporary
        if (-not [IO.File]::Exists($temporary)) {
            # Argument errors from older CLIs may be stdout-only.
            if ($stdout) { return (($stdout -join "`n") | ConvertFrom-Json) }
            throw 'CLI did not return a response.'
        }
        return ([IO.File]::ReadAllText($temporary, [Text.Encoding]::UTF8) | ConvertFrom-Json)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Resolve-OptionCatalog {
    $optionQuery = $Query.Trim()
    try {
        if ($StrikePrice -and $StrikePrice -notmatch '^[0-9]+(?:\.[0-9]+)?$') { throw 'Invalid strike price.' }
        $version = Invoke-OptionCli @('version')
        if (-not $version.success -or $version.data.option_catalog_implemented -ne $true -or
            $version.data.option_catalog_version -ne 1) {
            return [ordered]@{status='error'; code='OPTION_CATALOG_UNSUPPORTED'; message=([regex]::Unescape('\u5f53\u524d CLI \u4e0d\u652f\u6301\u671f\u6743\u76ee\u5f55\uff0c\u8bf7\u66f4\u65b0 CLI\u3002'))}
        }
        $statusArgs = @('status') + $RootArgs
        if ($ClientPid -gt 0) { $statusArgs += @('--pid', [string]$ClientPid) }
        $state = Invoke-OptionCli $statusArgs
        if ($state.error.code -eq 'PERMISSION_DENIED') {
            return [ordered]@{status='error'; code='PERMISSION_DENIED'; message=[string]$state.error.message}
        }
        if ($state.data.status.option_catalog_implemented -ne $true -or
            $state.data.status.option_catalog_version -ne 1) {
            return [ordered]@{status='error'; code='OPTION_CATALOG_UNSUPPORTED'; message=([regex]::Unescape('\u5f53\u524d\u5ba2\u6237\u7aef\u4e0d\u652f\u6301\u671f\u6743\u76ee\u5f55\uff0c\u8bf7\u66f4\u65b0\u5ba2\u6237\u7aef\u3002'))}
        }
        $selectedClientPid = [int]$state.data.selected_pid
        if ($selectedClientPid -le 0 -or ($ClientPid -gt 0 -and $selectedClientPid -ne $ClientPid)) {
            throw 'No uniquely selected EJClient process.'
        }
        $baseArguments = @('instrument-list') + $RootArgs + @('--pid', [string]$selectedClientPid, '--asset-type', 'option', '--limit', '200')
        if ($Exchange) { $baseArguments += @('--exchange', $Exchange) }
        if ($Commodity) { $baseArguments += @('--commodity', $Commodity) }
        if ($Month) { $baseArguments += @('--month', $Month) }
        $offset = 0
        $snapshot = ''
        $total = -1
        $allOptions = New-Object 'System.Collections.Generic.List[object]'
        do {
            $arguments = $baseArguments + @('--offset', [string]$offset)
            if ($snapshot) { $arguments += @('--snapshot', $snapshot) }
            $page = Invoke-OptionCli $arguments
            if (-not $page.success) {
                return [ordered]@{status='error'; code=[string]$page.error.code; message=[string]$page.error.message}
            }
            $data = $page.data
            if ($data.schema -ne 'plf-instrument-catalog/1' -or $data.asset_type -ne 'option' -or
                $data.scope -ne 'currently_listed' -or [int]$data.selected_pid -ne $selectedClientPid -or
                [int]$data.offset -ne $offset -or [int]$data.limit -ne 200 -or
                -not $data.snapshot -or $null -eq $data.total -or $null -eq $data.instruments -or
                $data.PSObject.Properties.Name -notcontains 'next_offset') { throw 'Invalid option catalog page.' }
            if ($snapshot -and ($snapshot -cne [string]$data.snapshot -or $total -ne [int]$data.total)) {
                throw 'Option snapshot changed during pagination.'
            }
            $snapshot = [string]$data.snapshot
            $total = [int]$data.total
            $items = @($data.instruments)
            if ($total -lt 0 -or [int]$data.count -ne $items.Count -or $items.Count -gt 200 -or
                $offset + $items.Count -gt $total) { throw 'Invalid option catalog count.' }
            foreach ($item in $items) {
                if ($item.asset_type -ne 'option' -or -not $item.key) { throw 'Invalid option metadata.' }
                $allOptions.Add($item)
            }
            if ($null -ne $data.next_offset) {
                if ([int]$data.next_offset -ne $offset + $items.Count -or
                    [int]$data.next_offset -le $offset -or [int]$data.next_offset -ge $total) { throw 'Invalid option pagination.' }
                $offset = [int]$data.next_offset
            } elseif ($allOptions.Count -ne $total) { throw 'Incomplete option catalog.' }
        } while ($null -ne $data.next_offset)

        $optionHits = @($allOptions | Where-Object { [string]$_.key -ceq $optionQuery })
        if ($optionHits.Count -eq 0) { $optionHits = @($allOptions | Where-Object { [string]$_.name -ceq $optionQuery }) }
        if ($optionHits.Count -eq 0) {
            $product = ''
            $wantedMonth = $Month
            $wantedSide = $CallPut
            $wantedStrike = $StrikePrice
            $parsed = [regex]::Match($optionQuery, '^(?<product>.+?)\s*(?<month>[0-9]{4}|[0-9]{6})\s*(?<side>\u8ba4\u8d2d|\u8ba4\u6cbd|\u770b\u6da8|\u770b\u8dcc|\u8d2d|\u6cbd|C|P)\s*(?<strike>[0-9]+(?:\.[0-9]+)?)?$', 'IgnoreCase')
            if ($parsed.Success) {
                $product = $parsed.Groups['product'].Value.Trim()
                if ($wantedMonth -and $wantedMonth -cne $parsed.Groups['month'].Value) { throw 'Conflicting option month.' }
                $wantedMonth = $parsed.Groups['month'].Value
                $side = $parsed.Groups['side'].Value
                $parsedSide = if ($side -match '^(\u8ba4\u8d2d|\u770b\u6da8|\u8d2d|C)$') { 'C' } else { 'P' }
                if ($wantedSide -and $wantedSide -ne $parsedSide) { throw 'Conflicting call/put condition.' }
                $wantedSide = $parsedSide
                if ($parsed.Groups['strike'].Success) {
                    if ($wantedStrike -and [decimal]::Parse($wantedStrike, [Globalization.CultureInfo]::InvariantCulture) -ne
                        [decimal]::Parse($parsed.Groups['strike'].Value, [Globalization.CultureInfo]::InvariantCulture)) { throw 'Conflicting strike condition.' }
                    $wantedStrike = $parsed.Groups['strike'].Value
                }
            } elseif ($optionQuery -and $optionQuery -notmatch '\|') {
                $product = $optionQuery -replace '\u671f\u6743$', ''
            }
            if ($wantedStrike -and $wantedStrike -notmatch '^[0-9]+(?:\.[0-9]+)?$') { throw 'Invalid strike price.' }
            $productCodes = @()
            if ($product) {
                $seedFile = Join-Path $SkillDirectory 'references\contracts.seed.json'
                if ([IO.File]::Exists($seedFile)) {
                    $optionSeed = [IO.File]::ReadAllText($seedFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
                    $productCodes = @($optionSeed.products | Where-Object {
                        [string]$_.code -ieq $product -or @($_.names | Where-Object { [string]$_ -ieq $product }).Count -gt 0
                    })
                }
            }
            # Unknown complete keys must never degrade to a guessed contract.
            if ($optionQuery -notmatch '\|') {
                $optionHits = @($allOptions | Where-Object {
                    $item = $_
                    $productMatch = -not $product -or [string]$item.commodity -ieq $product -or
                        [string]$item.commodity_name -eq $product -or
                        @($productCodes | Where-Object { [string]$_.code -ieq [string]$item.commodity -and [string]$_.ex -ieq [string]$item.exchange }).Count -gt 0
                    $productMatch -and (-not $wantedMonth -or [string]$item.month -ceq $wantedMonth) -and
                        (-not $wantedSide -or [string]$item.call_put -eq $wantedSide) -and
                        (-not $wantedStrike -or [decimal]::Parse([string]$item.strike_price, [Globalization.CultureInfo]::InvariantCulture) -eq
                            [decimal]::Parse($wantedStrike, [Globalization.CultureInfo]::InvariantCulture))
                })
            }
        }
        # Explicit conditions also constrain exact key/name matches.
        $optionHits = @($optionHits | Where-Object {
            (-not $CallPut -or [string]$_.call_put -eq $CallPut) -and
            (-not $StrikePrice -or [decimal]::Parse([string]$_.strike_price, [Globalization.CultureInfo]::InvariantCulture) -eq
                [decimal]::Parse($StrikePrice, [Globalization.CultureInfo]::InvariantCulture))
        })
        if ($optionHits.Count -eq 1) {
            return [ordered]@{status='resolved'; query=$optionQuery; asset_type='option'; name=[string]$optionHits[0].name;
                key=[string]$optionHits[0].key; selected_pid=$selectedClientPid; scope='currently_listed'}
        }
        if ($optionHits.Count -gt 1) {
            return [ordered]@{status='ambiguous'; code='OPTION_CONTRACT_REQUIRED'; query=$optionQuery; asset_type='option';
                count=$optionHits.Count; candidates=$optionHits; message=([regex]::Unescape('\u8bf7\u8865\u9f50\u54c1\u79cd\u3001\u6708\u4efd\u3001\u8ba4\u8d2d/\u8ba4\u6cbd\u548c\u884c\u6743\u4ef7\uff0c\u660e\u786e\u552f\u4e00\u5408\u7ea6\u3002'))}
        }
        return [ordered]@{status='not_found'; code='OPTION_NOT_IN_CURRENT_CATALOG'; query=$optionQuery; asset_type='option';
            candidates=@(); message=([regex]::Unescape('\u5f53\u524d\u6302\u724c\u671f\u6743\u76ee\u5f55\u672a\u627e\u5230\u5339\u914d\u5408\u7ea6\uff1b\u5df2\u6458\u724c\u5408\u7ea6\u8d85\u51fa\u672c\u671f\u76ee\u5f55\u8303\u56f4\uff0c\u4e0d\u80fd\u636e\u6b64\u5224\u65ad\u5408\u7ea6\u4e0d\u5b58\u5728\u3002'))}
    } catch {
        return [ordered]@{status='error'; code='OPTION_CATALOG_QUERY_FAILED'; message=$_.Exception.Message}
    }
}

function Write-OptionResolution {
    $result = Resolve-OptionCatalog
    Write-JsonResult $result
    if ($result.status -eq 'resolved') { exit 0 }
    if ($result.status -eq 'ambiguous') { exit 2 }
    if ($result.status -eq 'not_found') { exit 3 }
    exit 32
}

$OptionRequested = $AssetType -eq 'option' -or $Exchange -or $Commodity -or $Month -or $CallPut -or $StrikePrice -or
    $Query -match '\||\u671f\u6743|\u8ba4\u8d2d|\u8ba4\u6cbd|\u770b\u6da8|\u770b\u8dcc|[0-9]\s*[CP\u8d2d\u6cbd]\s*[0-9]'
if ($Action -eq 'Resolve' -and $OptionRequested) { Write-OptionResolution }

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

# Exact option names without an obvious option suffix are checked only after
# all established future/stock resolution paths have declined the query.
$optionFallback = Resolve-OptionCatalog
if ($optionFallback.status -eq 'resolved' -or $optionFallback.status -eq 'ambiguous') {
    Write-JsonResult $optionFallback
    exit $(if ($optionFallback.status -eq 'resolved') { 0 } else { 2 })
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
