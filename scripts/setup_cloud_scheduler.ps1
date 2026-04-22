param(
    [string]$ProjectId = "Golfer-a4ad7",
    [string]$Location = "europe-west1",
    [string]$ServiceName = "Golfer-api",
    [string]$TimeZone = "Africa/Nairobi",
    [string]$InternalTokenSecret = "INTERNAL_API_TOKEN",
    [string]$ServiceUrl = "",
    [string]$ClientVersionHeader = "X-App-Version",
    [string]$ClientVersion = "2.0"
)

$ErrorActionPreference = "Stop"

function Invoke-Gcloud {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    Write-Host ("gcloud " + ($Args -join " "))
    & gcloud @Args
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud command failed with exit code $LASTEXITCODE"
    }
}

function Resolve-ServiceUrl {
    $serviceJson = & gcloud run services describe $ServiceName `
        "--region=$Location" `
        "--project=$ProjectId" `
        "--format=json"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($serviceJson | Out-String))) {
        throw "Could not describe Cloud Run service $ServiceName in $Location."
    }

    $service = $serviceJson | ConvertFrom-Json
    $envEntries = @()
    if ($service.spec -and $service.spec.template -and $service.spec.template.spec -and $service.spec.template.spec.containers) {
        $containers = @($service.spec.template.spec.containers)
        if ($containers.Count -gt 0 -and $containers[0].env) {
            $envEntries = @($containers[0].env)
        }
    }

    foreach ($entry in $envEntries) {
        if ($entry.name -eq "BASE_PUBLIC_URL" -and -not [string]::IsNullOrWhiteSpace($entry.value)) {
            return $entry.value.Trim()
        }
    }

    if ($service.status -and -not [string]::IsNullOrWhiteSpace($service.status.url)) {
        return $service.status.url.Trim()
    }

    throw "Could not resolve a service URL from BASE_PUBLIC_URL or status.url."
}

function Upsert-HttpJob {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Schedule,
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$HeaderValue
    )

    $baseArgs = @(
        "--project=$ProjectId",
        "--location=$Location",
        "--schedule=$Schedule",
        "--time-zone=$TimeZone",
        "--http-method=GET",
        "--uri=$Uri",
        "--attempt-deadline=300s",
        "--description=$Description"
    )

    $jobRefRaw = & gcloud scheduler jobs list `
        "--location=$Location" `
        "--project=$ProjectId" `
        "--filter=name:$Name" `
        "--format=value(name)"
    $jobRef = if ($null -eq $jobRefRaw) { "" } else { ($jobRefRaw | Out-String).Trim() }
    $exists = -not [string]::IsNullOrWhiteSpace($jobRef)

    if ($exists) {
        $args = @(
            "scheduler",
            "jobs",
            "update",
            "http",
            $Name,
            "--update-headers=X-Internal-Token=$HeaderValue,$ClientVersionHeader=$ClientVersion"
        ) + $baseArgs
        Invoke-Gcloud -Args $args
    } else {
        $args = @(
            "scheduler",
            "jobs",
            "create",
            "http",
            $Name,
            "--headers=X-Internal-Token=$HeaderValue,$ClientVersionHeader=$ClientVersion"
        ) + $baseArgs
        Invoke-Gcloud -Args $args
    }
}

Invoke-Gcloud -Args @("config", "set", "project", $ProjectId)

if ([string]::IsNullOrWhiteSpace($ServiceUrl)) {
    $ServiceUrl = Resolve-ServiceUrl
}

$internalToken = (& gcloud secrets versions access latest "--secret=$InternalTokenSecret" "--project=$ProjectId").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($internalToken)) {
    throw "Could not load INTERNAL_API_TOKEN from Secret Manager."
}

$jobs = @(
    @{
        Name = "Golfer-mpesa-reconcile-pending"
        Schedule = "*/15 * * * *"
        Uri = "$ServiceUrl/tasks/mpesa-reconcile-pending"
        Description = "Reconcile pending M-Pesa transactions every 15 minutes."
    },
    @{
        Name = "Golfer-session-cleanup-midnight"
        Schedule = "0 0 * * *"
        Uri = "$ServiceUrl/tasks/session-cleanup"
        Description = "Clean expired upload sessions each midnight EAT."
    },
    @{
        Name = "Golfer-health-check-daily"
        Schedule = "5 0 * * *"
        Uri = "$ServiceUrl/tasks/health-check"
        Description = "Run daily health checks at 00:05 EAT."
    },
    @{
        Name = "Golfer-nightly-maintenance"
        Schedule = "55 23 * * *"
        Uri = "$ServiceUrl/tasks/nightly"
        Description = "Run nightly cleanup and snapshot generation at 23:55 EAT."
    }
)

foreach ($job in $jobs) {
    Upsert-HttpJob `
        -Name $job.Name `
        -Schedule $job.Schedule `
        -Uri $job.Uri `
        -Description $job.Description `
        -HeaderValue $internalToken
}

Write-Host ""
Write-Host "Cloud Scheduler jobs now configured in $Location for $ServiceUrl"
Invoke-Gcloud -Args @(
    "scheduler",
    "jobs",
    "list",
    "--location=$Location",
    "--project=$ProjectId",
    "--format=table(name,schedule,timeZone,state,httpTarget.uri)"
)
