param(
    [string]$ProjectId = "Golfer-a4ad7",
    [string]$Location = "europe-west1",
    [string]$ServiceName = "Golfer-api"
)

$ErrorActionPreference = "Stop"

function Invoke-GcloudJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    $raw = & gcloud @Args
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud command failed with exit code $LASTEXITCODE"
    }

    $text = ($raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    return $text | ConvertFrom-Json
}

function Normalize-SecretName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $trimmed = $Value.Trim()
    if ($trimmed -match "/secrets/([^/]+)$") {
        return $Matches[1]
    }

    return $trimmed
}

$allSecrets = Invoke-GcloudJson -Args @(
    "secrets",
    "list",
    "--project=$ProjectId",
    "--format=json"
)

if ($null -eq $allSecrets) {
    $allSecrets = @()
} elseif (-not ($allSecrets -is [System.Array])) {
    $allSecrets = @($allSecrets)
}

$service = Invoke-GcloudJson -Args @(
    "run",
    "services",
    "describe",
    $ServiceName,
    "--region=$Location",
    "--project=$ProjectId",
    "--format=json"
)

$envEntries = @()
if (
    $service.spec -and
    $service.spec.template -and
    $service.spec.template.spec -and
    $service.spec.template.spec.containers
) {
    $containers = @($service.spec.template.spec.containers)
    if ($containers.Count -gt 0 -and $containers[0].env) {
        $envEntries = @($containers[0].env)
    }
}

$referencedSecrets = @(
    $envEntries |
        Where-Object {
            $_.valueFrom -and
            $_.valueFrom.secretKeyRef -and
            -not [string]::IsNullOrWhiteSpace($_.valueFrom.secretKeyRef.name)
        } |
        ForEach-Object { $_.valueFrom.secretKeyRef.name.Trim() } |
        Sort-Object -Unique
)

$allSecretNames = @($allSecrets | ForEach-Object { Normalize-SecretName -Value $_.name }) | Sort-Object
$unusedSecrets = @($allSecretNames | Where-Object { $referencedSecrets -notcontains $_ })
$duplicateGroups = @(
    $allSecretNames |
        Group-Object { $_.ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 }
)

Write-Host ""
Write-Host "Secret Manager audit"
Write-Host "Project: $ProjectId"
Write-Host "Cloud Run service: $ServiceName"
Write-Host ""
Write-Host ("Total secrets in project: {0}" -f $allSecretNames.Count)
Write-Host ("Secrets referenced by Cloud Run env: {0}" -f $referencedSecrets.Count)
Write-Host ("Secrets not referenced by Cloud Run env: {0}" -f $unusedSecrets.Count)

Write-Host ""
Write-Host "Referenced secrets"
foreach ($name in $referencedSecrets) {
    Write-Host ("  - {0}" -f $name)
}

Write-Host ""
Write-Host "Unreferenced secrets"
if ($unusedSecrets.Count -eq 0) {
    Write-Host "  none"
} else {
    foreach ($name in $unusedSecrets) {
        Write-Host ("  - {0}" -f $name)
    }
}

Write-Host ""
Write-Host "Likely duplicate names (case-insensitive)"
if ($duplicateGroups.Count -eq 0) {
    Write-Host "  none"
} else {
    foreach ($group in $duplicateGroups) {
        Write-Host ("  - {0}" -f (($group.Group | Sort-Object) -join ", "))
    }
}

Write-Host ""
Write-Host "Review any unreferenced or duplicate secret before deleting it."
Write-Host "Cloud Scheduler in this repo reads INTERNAL_API_TOKEN from Secret Manager, so keep that one."
