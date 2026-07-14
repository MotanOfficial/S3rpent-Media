# Sync Mineradio 3D scene into S3rpent_Media/resources/audio3d for WebEngine embed.
# Run from repo root: .\scripts\sync_mineradio_audio3d.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mineradioRoot = Join-Path (Split-Path -Parent $repoRoot) "Mineradio"
$destRoot = Join-Path $repoRoot "resources\audio3d"
$srcIndex = Join-Path $mineradioRoot "public\index.html"
$srcVendor = Join-Path $mineradioRoot "public\vendor"

if (-not (Test-Path $srcIndex)) {
    Write-Error "Mineradio not found at $mineradioRoot (expected public\index.html)"
}

New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $destRoot "vendor") | Out-Null

Copy-Item -Force (Join-Path $srcVendor "three.r128.min.js") (Join-Path $destRoot "vendor\")
Copy-Item -Force (Join-Path $srcVendor "music-tempo.min.js") (Join-Path $destRoot "vendor\")
Copy-Item -Force (Join-Path $srcVendor "gsap.min.js") (Join-Path $destRoot "vendor\")

$scenePath = Join-Path $destRoot "scene.html"
Copy-Item -Force $srcIndex $scenePath

$html = Get-Content -Raw -Encoding UTF8 $scenePath

if ($html -notmatch "s3rpent-embed.css") {
    $html = $html.Replace("</head>", "<link rel=`"stylesheet`" href=`"s3rpent-embed.css`">`n</head>")
}

$embedInit = @'
(function s3rpentEmbedInit(){
  window.S3RPENT_EMBED = true;
  window.s3rpentAudio = { bass:0, mid:0, treble:0, energy:0, beat:0, vocal:0, playing:false };
  window.s3rpentApplyAudio = function(o){ if(o) Object.assign(window.s3rpentAudio, o); };
  window.s3rpentSetCoverUrl = function(url){
    if(!url || typeof loadCoverFromUrl !== 'function') return;
    try { loadCoverFromUrl(url, {}); } catch(e) { console.warn('[s3rpent] cover', e); }
  };
  window.s3rpentSetPreset = function(i){
    if(typeof setPreset === 'function') setPreset(i, { silent:true, noSave:true, skipTransition:false });
  };
  document.documentElement.classList.add('s3rpent-embed');
  if(document.body){
    document.body.classList.remove('splash-active','splash-revealing');
    document.body.classList.add('immersive-mode','s3rpent-embed');
  }
  try { if(typeof setPreset === 'function' && typeof fx !== 'undefined') setPreset(fx.preset || 0, { silent:true, noSave:true, skipTransition:true, preserveCamera:true }); } catch(e) {}
})();
'@

if ($html -notmatch "s3rpentEmbedInit") {
    $html = $html.Replace("animate();", ($embedInit + "`nanimate();"))
}

$fftNeedle = "if (analyser && playing && audio && !audio.paused) {"
$fftPatchPath = Join-Path $destRoot "s3rpent-fft-patch.js"
if ($html.Contains($fftNeedle) -and ($html -notmatch "window\.S3RPENT_EMBED && window\.s3rpentAudio")) {
    $fftPatch = Get-Content -Raw -Encoding UTF8 $fftPatchPath
    $html = $html.Replace($fftNeedle, $fftPatch.TrimEnd())
}

[System.IO.File]::WriteAllText($scenePath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host ("Synced Mineradio 3D scene to " + $destRoot)
