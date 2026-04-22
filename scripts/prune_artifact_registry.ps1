param(
    [string]$ProjectId = "Golfer-a4ad7",
    [string]$Location = "europe-west1",
    [string]$Repository = "cloud-run-source-deploy",
    [string]$Package = "Golfer-api",
    [string]$ServiceName = "Golfer-api",
    [int]$KeepLatest = 5,
    [int]$ProtectRecentRevisions = 10,
    [switch]$Apply
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

function Normalize-Digest {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $trimmed = $Value.Trim()
    if ($trimmed -match "@(sha256:[a-f0-9]+)$") {
        return $Matches[1]
    }
    if ($trimmed -match "^(sha256:[a-f0-9]+)$") {
        return $trimmed
    }

    return ""
}

$packagePath = "{0}-docker.pkg.dev/{1}/{2}/{3}" -f $Location, $ProjectId, $Repository, $Package

$images = Invoke-GcloudJson -Args @(
    "artifacts",
    "docker",
    "images",
    "list",
    $packagePath,
    "--include-tags",
    "--format=json"
)

if ($null -eq $images) {
    $images = @()
} elseif (-not ($images -is [System.Array])) {
    $images = @($images)
}

if ($images.Count -eq 0) {
    Write-Host "No Artifact Registry images found."
    exit 0
}

$images = @(
    $images |
        Sort-Object { [DateTimeOffset]$_.updateTime } -Descending
)

$revisions = Invoke-GcloudJson -Args @(
    "run",
    "revisions",
    "list",
    "--service=$ServiceName",
    "--region=$Location",
    "--project=$ProjectId",
    "--format=json"
)

if ($null -eq $revisions) {
    $revisions = @()
} elseif (-not ($revisions -is [System.Array])) {
    $revisions = @($revisions)
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

$protectedDigests = New-Object "System.Collections.Generic.HashSet[string]"

foreach ($image in ($images | Select-Object -First $KeepLatest)) {
    $digest = Normalize-Digest -Value $image.version
    if ($digest) {
        [void]$protectedDigests.Add($digest)
    }
}

$recentRevisions = @(
    $revisions |
        Sort-Object { [DateTimeOffset]$_.metadata.creationTimestamp } -Descending |
        Select-Object -First $ProtectRecentRevisions
)

foreach ($revision in $recentRevisions) {
    $digest = Normalize-Digest -Value $revision.status.imageDigest
    if ($digest) {
        [void]$protectedDigests.Add($digest)
    }
}

if ($service.status -and $service.status.traffic) {
    foreach ($traffic in @($service.status.traffic)) {
        if ([string]::IsNullOrWhiteSpace($traffic.revisionName)) {
            continue
        }

        $revision = @($revisions | Where-Object { $_.metadata.name -eq $traffic.revisionName } | Select-Object -First 1)
        if ($revision.Count -eq 0) {
            continue
        }

        $digest = Normalize-Digest -Value $revision[0].status.imageDigest
        if ($digest) {
            [void]$protectedDigests.Add($digest)
        }
    }
}

$deleteCandidates = @()
foreach ($image in $images) {
    $digest = Normalize-Digest -Value $image.version
    if (-not $digest) {
        continue
    }

    if ($protectedDigests.Contains($digest)) {
        continue
    }

    $deleteCandidates += [PSCustomObject]@{
        Digest = $digest
        Updated = $image.updateTime
        Ref = "{0}@{1}" -f $packagePath, $digest
    }
}

Write-Host ""
Write-Host "Artifact Registry prune plan"
Write-Host "Project: $ProjectId"
Write-Host "Repository: $Repository"
Write-Host "Package: $Package"
Write-Host ("Total images found: {0}" -f $images.Count)
Write-Host ("Protected digests: {0}" -f $protectedDigests.Count)
Write-Host ("Delete candidates: {0}" -f $deleteCandidates.Count)

if ($deleteCandidates.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing to delete."
    exit 0
}

Write-Host ""
Write-Host "First delete candidates"
foreach ($candidate in ($deleteCandidates | Select-Object -First 20)) {
    Write-Host ("  - {0}  ({1})" -f $candidate.Ref, $candidate.Updated)
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. Re-run with -Apply to delete old images."
    Write-Host "This script keeps the latest image digests plus recent revision digests for rollback safety."
    exit 0
}

Write-Host ""
Write-Host "Deleting old images..."
foreach ($candidate in $deleteCandidates) {
    Write-Host ("Deleting {0}" -f $candidate.Ref)
    & gcloud artifacts docker images delete $candidate.Ref --quiet --delete-tags
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete $($candidate.Ref)"
    }
}

Write-Host ""
Write-Host ("Deleted {0} image(s)." -f $deleteCandidates.Count)
