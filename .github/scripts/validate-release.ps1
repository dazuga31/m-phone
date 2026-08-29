[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

Push-Location $Root

try {
    $requiredFiles = @(
        "package.json",
        "VERSION",
        "README.md",
        "INSTALLATION.md",
        "CONFIGURATION.md",
        "DEPENDENCIES.md",
        "API.md",
        "EXPORTS.md",
        "SECURITY.md",
        "LICENSE",
        "client.lua",
        "server.lua",
        "web/index.html"
    )

    foreach ($path in $requiredFiles) {
        Assert-Condition (Test-Path -LiteralPath $path) "Required release file is missing: $path"
    }

    $manifest = Get-Content -Raw -LiteralPath "package.json" | ConvertFrom-Json
    foreach ($side in @("shared", "client", "server")) {
        $entries = @($manifest.$side)
        Assert-Condition ($entries.Count -gt 0) "package.json has no '$side' entrypoints."
        foreach ($entry in $entries) {
            Assert-Condition (Test-Path -LiteralPath $entry) "Missing $side entrypoint: $entry"
        }
    }

    $version = (Get-Content -Raw -LiteralPath "VERSION").Trim()
    Assert-Condition ($version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') "Invalid VERSION value: $version"
    $changelog = Get-Content -Raw -LiteralPath "CHANGELOG.md"
    Assert-Condition ($changelog.Contains("## [$version]")) "CHANGELOG.md has no section for $version."

    $trackedFiles = @(git ls-files)
    Assert-Condition ($LASTEXITCODE -eq 0) "Unable to enumerate tracked files."

    $forbiddenPatterns = @(
        '(^|/)PhoneApps/Camera/camera_storage_local\.lua$',
        '(^|/)(node_modules|src|_mock)(/|$)',
        '\.(db|sqlite|sqlite3|log|map|zip|rar|7z)$'
    )

    foreach ($path in $trackedFiles) {
        foreach ($pattern in $forbiddenPatterns) {
            Assert-Condition ($path -notmatch $pattern) "Forbidden release file is tracked: $path"
        }
    }

    $secretPattern = @(
        ('github' + '_pat_'),
        ('gh' + '[pousr]_'),
        ('HELIX' + '_USER_TOKEN\s*='),
        ('sk' + '-[A-Za-z0-9_-]{20,}'),
        ('-----BEGIN ' + '(RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----')
    ) -join '|'
    $secretMatches = @(git grep -n -I -E $secretPattern -- . 2>$null)
    if ($LASTEXITCODE -eq 0) {
        throw "Potential tracked secret detected:`n$($secretMatches -join "`n")"
    }
    Assert-Condition ($LASTEXITCODE -eq 1) "Tracked secret scan failed."

    $luaParser = Get-Command "luaparse" -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $luaParser) "luaparse is not installed."

    $luaFiles = @(Get-ChildItem -Recurse -File -Filter "*.lua")
    foreach ($file in $luaFiles) {
        Get-Content -Raw -LiteralPath $file.FullName |
            & $luaParser.Source |
            Out-Null
        Assert-Condition ($LASTEXITCODE -eq 0) "Lua parse failed: $($file.FullName)"
    }

    $javascriptFiles = @($trackedFiles | Where-Object { $_ -match '\.js$' })
    foreach ($path in $javascriptFiles) {
        & node --check $path | Out-Null
        Assert-Condition ($LASTEXITCODE -eq 0) "JavaScript parse failed: $path"
    }

    $repositoryRoot = (Get-Location).Path
    $markdownFiles = @(Get-ChildItem -Recurse -File -Filter "*.md")
    $relativeLinkCount = 0

    foreach ($file in $markdownFiles) {
        $contents = Get-Content -Raw -LiteralPath $file.FullName
        $matches = [regex]::Matches($contents, '\[[^\]]*\]\(([^)]+)\)')

        foreach ($match in $matches) {
            $target = $match.Groups[1].Value.Trim()
            if (
                $target -match '^(https?://|mailto:|#)' -or
                $target -match '^<'
            ) {
                continue
            }

            $relative = (($target -split '#')[0] -split '\?')[0]
            if ([string]::IsNullOrWhiteSpace($relative)) {
                continue
            }

            $relative = [Uri]::UnescapeDataString($relative)
            $resolved = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relative))
            Assert-Condition (Test-Path -LiteralPath $resolved) (
                "Broken relative Markdown link in {0}: {1}" -f
                $file.FullName.Substring($repositoryRoot.Length + 1),
                $target
            )
            $relativeLinkCount++
        }
    }

    $apiDocumentation = (
        (Get-Content -Raw -LiteralPath "API.md") +
        "`n" +
        (Get-Content -Raw -LiteralPath "EXPORTS.md")
    )
    $exportNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $exportPattern = 'exports\s*\(\s*["'']m-phone["'']\s*,\s*["'']([^"'']+)["'']'

    foreach ($file in $luaFiles) {
        $contents = Get-Content -Raw -LiteralPath $file.FullName
        foreach ($match in [regex]::Matches($contents, $exportPattern)) {
            [void]$exportNames.Add($match.Groups[1].Value)
        }
    }

    foreach ($exportName in $exportNames) {
        Assert-Condition ($apiDocumentation.Contains($exportName)) (
            "Static export is missing from API documentation: $exportName"
        )
    }

    Write-Host "VALIDATION_OK"
    Write-Host "version=$version"
    Write-Host "lua_files=$($luaFiles.Count)"
    Write-Host "javascript_files=$($javascriptFiles.Count)"
    Write-Host "markdown_files=$($markdownFiles.Count)"
    Write-Host "relative_links=$relativeLinkCount"
    Write-Host "static_exports=$($exportNames.Count)"
}
finally {
    Pop-Location
}
