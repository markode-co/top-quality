$versions = @(
  "20260312013000",
  "20260312020000",
  "20260312023000",
  "20260312040500",
  "20260312043000",
  "20260312044500",
  "20260312045500",
  "20260312050000",
  "20260312052000",
  "20260312053000",
  "20260312054000",
  "20260312120000",
  "20260312121000",
  "20260313190000",
  "20260313191000",
  "20260313193000",
  "20260313194500",
  "20260313195500",
  "20260313213000",
  "20260313220000",
  "20260313223000",
  "20260314090000",
  "20260314091000",
  "20260314123000",
  "20260314124500",
  "20260314131500",
  "20260314133500",
  "20260314134000",
  "20260314134500",
  "20260314160000",
  "20260314161000"
)

New-Item -ItemType Directory -Path "supabase/migrations" -Force | Out-Null

foreach ($version in $versions) {
  $filePath = "supabase/migrations/${version}_recovered_placeholder.sql"
  if (-not (Test-Path $filePath)) {
    @(
      "-- Recovered placeholder migration $version",
      "-- Original local file was missing; remote history already contains this version.",
      "-- Intentionally left blank."
    ) | Set-Content -Path $filePath -Encoding UTF8
  }
}

Write-Host "placeholder migrations created"
