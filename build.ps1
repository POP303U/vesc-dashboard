param([string]$VescTool = "vesc_tool")

$version = (git describe --tags --always --dirty).Trim()
New-Item -ItemType Directory -Force build | Out-Null

# stamp the version into a copy of ui.qml, UTF-8 without BOM so the degree signs survive
$text = [IO.File]::ReadAllText("$PWD\ui.qml", [Text.Encoding]::UTF8).Replace("@VERSION@", $version)
[IO.File]::WriteAllText("$PWD\build\ui.qml", $text, (New-Object Text.UTF8Encoding $false))

Copy-Item pkgdesc.qml, README.md build\ -Force

Push-Location build
& $VescTool --buildPkgFromDesc pkgdesc.qml
Pop-Location