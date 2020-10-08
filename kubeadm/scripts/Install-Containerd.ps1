Param(
    [parameter(HelpMessage = "ContainerD version to use")]
    [string] $ContainerDVersion = "1.4.1",
    [parameter(HelpMessage = "Run container as a Windows Service")]
    [bool] $RunAsService = $true
)

$ErrorActionPreference = 'Stop'

function DownloadFile($destination, $source) {
    Write-Host("Downloading $source to $destination")
    curl.exe --silent --fail -Lo $destination $source

    if (!$?) {
        Write-Error "Download $source failed"
        exit 1
    }
}

$global:ConainterDPath = "$env:ProgramFiles\containerd"
mkdir -Force $global:ConainterDPath
DownloadFile "$global:ConainterDPath\containerd.tar.gz" https://github.com/containerd/containerd/releases/download/v${ContainerDVersion}/containerd-${ContainerDVersion}-windows-amd64.tar.gz
tar.exe -xvf "$global:ConainterDPath\containerd.tar.gz" --strip=1 -C $global:ConainterDPath
$env:Path += ";$global:ConainterDPath"
[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
containerd.exe config default | Out-File "$global:ConainterDPath\config.toml" -Encoding ascii
#config file fixups
$config = Get-Content "$global:ConainterDPath\config.toml"
$config = $config -replace "bin_dir = (.)*$", "bin_dir = `"c:/opt/cni/bin`""
$config = $config -replace "conf_dir = (.)*$", "conf_dir = `"c:/etc/cni/net.d`""
$config | Set-Content "$global:ConainterDPath\config.toml" -Force 

mkdir -Force c:\opt\cni\bin
mkdir -Force c:\etc\cni\net.d

if ($RunAsService) {
    containerd.exe --register-service
    Get-Service
}
