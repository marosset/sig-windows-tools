Param(
    [parameter(HelpMessage = "ContainerD version to use")]
    [string] $ContainerDVersion = "1.4.1",
    [parameter(HelpMessage = "Run container as a Windows Service")]
    [bool] $RunAsService = $true,
    [bool] $ConfigureNatCNI = $true,
    [string] $netAdapterName = "Ethernet"
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

function CalculateSubNet {
    param (
        [string]$gateway,
        [int]$prefixLength
    )
    $len = $prefixLength
    $parts = $gateway.Split('.')
    $result = @()
    for ($i = 0; $i -le 3; $i++) {
        if ($len -ge 8) {
            $mask = 255

        }
        elseif ($len -gt 0) {
            $mask = ((256 - 2 * (8 - $len)))
        }
        else {
            $mask = 0
        }
        $len -= 8
        $result += ([int]$parts[$i] -band $mask)
    }

    $subnetIp = [string]::Join('.', $result)
    $cidr = 32 - $prefixLength
    return "${subnetIp}/$cidr"
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

if ($ConfigureNatCNI) {
    # get CNI plugins
    DownloadFile "c:\opt\cni\cni-plugins.zip" https://github.com/microsoft/windows-container-networking/releases/download/v0.2.0/windows-container-networking-cni-amd64-v0.2.0.zip
    Expand-Archive -Path "c:\opt\cni\cni-plugins.zip" -DestinationPath "c:\opt\cni\bin" -Force

    # run New-HnsNetwork -Type NAT -Name host first?

    $gateway = (Get-NetIPAddress -InterfaceAlias $netAdapterName -AddressFamily IPv4).IPAddress
    $prefixLength = (Get-NetIPAddress -InterfaceAlias $netAdapterName -AddressFamily IPv4).PrefixLength

    $subnet = CalculateSubNet -gateway $gateway -prefixLength $prefixLength

    @"
    {
        "cniVersion": "0.2.0",
        "name": "nat",
        "type": "nat",
        "master": "Ethernet",
        "ipam": {
            "subnet": "'$subnet'",
            "routes": [
                {
                    "GW": "'$gateway'"
                }
            ]
        },
        "capabilities": {
            "portMappings": true,
            "dns": true
        }
    }
"@ | Set-Content "c:\etc\cni\net.d\0-containerd-nat.json" -Force
}

if ($RunAsService) {
    containerd.exe --register-service
    Get-Service
}