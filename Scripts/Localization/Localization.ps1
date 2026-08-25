function Initialize-ResidueSweepLocalization {
    param([string]$Language)

    $supportedLanguages = @('zh-TW', 'en-US')
    $preferenceRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ResidueSweep'
    $script:ResidueSweepLanguagePreferencePath = Join-Path $preferenceRoot 'language.json'

    if ([string]::IsNullOrWhiteSpace($Language) -and (Test-Path -LiteralPath $script:ResidueSweepLanguagePreferencePath -PathType Leaf)) {
        try {
            $savedPreference = Get-Content -LiteralPath $script:ResidueSweepLanguagePreferencePath -Raw | ConvertFrom-Json
            $Language = [string]$savedPreference.Language
        }
        catch { }
    }

    if ($supportedLanguages -notcontains $Language) {
        $Language = 'zh-TW'
    }

    $script:ResidueSweepLanguage = $Language
    $script:ResidueSweepLocale = $null

    if ($Language -eq 'zh-TW') {
        $localePath = Join-Path $script:LocalesPath 'zh-TW.json'
        if (Test-Path -LiteralPath $localePath -PathType Leaf) {
            try {
                $script:ResidueSweepLocale = Get-Content -LiteralPath $localePath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                Write-Warning "Unable to load Traditional Chinese language resources: $($_.Exception.Message)"
            }
        }
    }

    [System.Globalization.CultureInfo]::CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo($Language)
    return $script:ResidueSweepLanguage
}
function Set-ResidueSweepLanguage {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('zh-TW', 'en-US')]
        [string]$Language,
        [switch]$DoNotPersist
    )

    Initialize-ResidueSweepLocalization -Language $Language | Out-Null
    if ($DoNotPersist) { return }

    $preferenceDirectory = Split-Path -Parent $script:ResidueSweepLanguagePreferencePath
    if (-not (Test-Path -LiteralPath $preferenceDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $preferenceDirectory -Force | Out-Null
    }
    @{ Language = $Language } | ConvertTo-Json | Set-Content -LiteralPath $script:ResidueSweepLanguagePreferencePath -Encoding UTF8
}

function Get-ResidueSweepText {
    param(
        [AllowEmptyString()]
        [string]$Text,
        [object[]]$Arguments
    )

    $localizedText = $Text
    if ($script:ResidueSweepLocale -and $script:ResidueSweepLocale.Strings) {
        $translation = $script:ResidueSweepLocale.Strings.PSObject.Properties[$Text]
        if ($translation) { $localizedText = [string]$translation.Value }
    }

    if ($Arguments) { return ($localizedText -f $Arguments) }
    return $localizedText
}

function Get-ResidueSweepLocalizedValue {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Categories', 'Groups', 'Features', 'Cleanup', 'Apps')]
        [string]$Section,
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$Property,
        [AllowNull()]
        $Fallback
    )

    if ($script:ResidueSweepLocale) {
        $sectionObject = $script:ResidueSweepLocale.PSObject.Properties[$Section]
        if ($sectionObject -and $sectionObject.Value) {
            $item = $sectionObject.Value.PSObject.Properties[$Id]
            if ($item -and $item.Value) {
                $localizedProperty = $item.Value.PSObject.Properties[$Property]
                if ($localizedProperty) { return $localizedProperty.Value }
            }
        }
    }

    return (Get-ResidueSweepText -Text ([string]$Fallback))
}

function Get-ResidueSweepLocalizedXaml {
    param([Parameter(Mandatory)][string]$Path)

    [xml]$document = Get-Content -LiteralPath $Path -Raw
    if (-not $script:ResidueSweepLocale -or -not $script:ResidueSweepLocale.Strings) {
        return $document.OuterXml
    }

    $userFacingAttributes = @('AutomationProperties.Name', 'Content', 'Header', 'Text', 'Title', 'ToolTip')
    foreach ($node in $document.SelectNodes('//*')) {
        foreach ($attribute in @($node.Attributes)) {
            if ($userFacingAttributes -notcontains $attribute.LocalName) { continue }
            $translated = Get-ResidueSweepText -Text ([string]$attribute.Value)
            if ($translated -ne $attribute.Value) { $attribute.Value = $translated }
        }
    }

    return $document.OuterXml
}
