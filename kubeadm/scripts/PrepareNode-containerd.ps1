<#
.SYNOPSIS
Assists with preparing a Windows VM prior to calling kubeadm join

.DESCRIPTION
This script assists with joining a Windows node to a cluster.
- Downloads Kubernetes binaries (kubelet, kubeadm) at the version specified
- Registers wins as a service in order to run kube-proxy and cni as DaemonSets.
- Registers kubelet as an nssm service. More info on nssm: https://nssm.cc/

.PARAMETER KubernetesVersion
Kubernetes version to download and use

.EXAMPLE
PS> .\PrepareNode.ps1 -KubernetesVersion v1.17.0

#>

Param(
    [parameter(Mandatory = $true, HelpMessage="Kubernetes version to use")]
    [string] $KubernetesVersion
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

if (!$KubernetesVersion.StartsWith("v")) {
    $KubernetesVersion = "v" + $KubernetesVersion
}

<#
if (!$ContainerDVersion.StartsWith("v")) {
    $ContainerDVersion = "v" + $ContainerDVersion
}

Write-Host "Using Kubernetes version: $KubernetesVersion"
$global:Powershell = (Get-Command powershell).Source
$global:PowershellArgs = "-ExecutionPolicy Bypass -NoProfile"
$global:KubernetesPath = "$env:SystemDrive\k"
$global:StartKubeletScript = "$global:KubernetesPath\StartKubelet.ps1"
$global:NssmInstallDirectory = "$env:ProgramFiles\nssm"
$kubeletBinPath = "$global:KubernetesPath\kubelet.exe"

mkdir -force "$global:KubernetesPath"
$env:Path += ";$global:KubernetesPath"
[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)

DownloadFile $kubeletBinPath https://dl.k8s.io/$KubernetesVersion/bin/windows/amd64/kubelet.exe
DownloadFile "$global:KubernetesPath\kubeadm.exe" https://dl.k8s.io/$KubernetesVersion/bin/windows/amd64/kubeadm.exe
DownloadFile "$global:KubernetesPath\wins.exe" https://github.com/rancher/wins/releases/download/v0.0.4/wins.exe

$global:ConainterDPath = "$env:ProgramFiles\containerd"
mkdir -force $global:ConainterDPath
DownloadFile "$global:ConainterDPath\containerd.tar.gz" https://github.com/containerd/containerd/releases/download/v1.4.1/containerd-1.4.1-windows-amd64.tar.gz
tar.exe -xvf "$global:ConainterDPath\containerd.tar.gz" --strip=1 -C $global:ConainterDPath
$env:Path += ";$global:ConainterDPath"
[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
containerd.exe config default | Out-File "$global:ConainterDPath\config.toml" -Encoding ascii
#config file fixups
$config = Get-Content "$global:ConainterDPath\config.toml"
$config = $config -replace "bin_dir = (.)*$", "bin_dir = `"c:/opt/cni/bin`""
$config = $config -replace "conf_dir = (.)*$", "conf_dir = `"c:/etc/cni/net.d`""
$config | Set-Content "$global:ConainterDPath\config.toml" -Force 
#containerd.exe --register-service
#Get-Service -Name "containerd" | Start-Service

#>

<#
mkdir -force c:\opt\cni\bin
mkdir -force c:\etc\cni\net.d
DownloadFile c:\opt\cni\cni-plugins.tgz https://github.com/containernetworking/plugins/releases/download/v0.8.7/cni-plugins-windows-amd64-v0.8.7.tgz
tar -xvf c:\opt\cni\cni-plugins.tgz -C c:\opt\cni\bin

@"
{
    "name":  "flannel.4096",
    "cniVersion":  "0.3.0",
    "type":  "flannel",
    "capabilities":  {
                         "dns":  true
                     },
    "delegate":  {
                     "type":  "win-overlay",
                     "policies":  [
                                      {
                                          "Name":  "EndpointPolicy",
                                          "Value":  {
                                                        "Type":  "OutBoundNAT",
                                                        "ExceptionList":  [
                                                                              "10.96.0.0/12",
                                                                              "10.244.0.0/16"
                                                                          ]
                                                    }
                                      },
                                      {
                                          "Name":  "EndpointPolicy",
                                          "Value":  {
                                                        "Type":  "ROUTE",
                                                        "DestinationPrefix":  "10.96.0.0/12",
                                                        "NeedEncap":  true
                                                    }
                                      }
                                  ]
                 }
}
"@ | Set-Content c:\etc\cni\net.d\net.json -Force

DownloadFile $global:KubernetesPath\hns.psm1 https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/hns.psm1
Import-Module $global:KubernetesPath\hns.psm1
Get-HnsNetwork | Remove-HnsNetwork
#New-HnsNetowrk -Type NAT -Name host

New-HNSNetwork -Type Overlay -AddressPrefix "192.168.255.0/30" -Gateway "192.168.255.1" -Name "External" -AdapterName "$AdapterName" -SubnetPolicies @(@{Type = "VSID"; VSID = 9999; })

# set up flannel
DownloadFile c:\k\flanneld.exe https://github.com/coreos/flannel/releases/download/v0.12.0/flanneld.exe
New-Item C:\etc\kube-flannel\ -Force -ItemType Directory | Out-Null
@"
{
  "Network": "10.244.0.0/16",
  "Backend": {
    "Type": "vxlan",
    "VNI": 4096,
    "Port": 4789
  }
}
"@ | Set-Content C:\etc\kube-flannel\net-conf.json -Force | Out-Null

#>

## Create host network to allow kubelet to schedule hostNetwork pods
#Write-Host "Creating Docker host network"
#docker network create -d nat host

#Write-Host "Registering wins service"
#wins.exe srv app run --register
#start-service rancher-wins

mkdir -force C:\var\log\kubelet
mkdir -force C:\var\lib\kubelet\etc\kubernetes
mkdir -force C:\etc\kubernetes\pki
New-Item -path C:\var\lib\kubelet\etc\kubernetes\pki -type SymbolicLink -value C:\etc\kubernetes\pki\

$StartKubeletFileContent = '$FileContent = Get-Content -Path "/var/lib/kubelet/kubeadm-flags.env"
$global:KubeletArgs = $FileContent.Trim("KUBELET_KUBEADM_ARGS=`"")

# $netId = docker network ls -f name=host --format "{{ .ID }}"

# if ($netId.Length -lt 1) {
#     docker network create -d nat host
# }

$cmd = "C:\k\kubelet.exe $global:KubeletArgs --cert-dir=$env:SYSTEMDRIVE\var\lib\kubelet\pki --config=/var/lib/kubelet/config.yaml --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --hostname-override=$(hostname) --pod-infra-container-image=`"mcr.microsoft.com/oss/kubernetes/pause:1.4.0`" --enable-debugging-handlers --cgroups-per-qos=false --enforce-node-allocatable=`"`" --resolv-conf=`"`" --log-dir=/var/log/kubelet --logtostderr=false --image-pull-progress-deadline=20m --container-runtime=remote --container-runtime-endpoint=npipe://./pipe/containerd-containerd"

Invoke-Expression $cmd'
Set-Content -Path $global:StartKubeletScript -Value $StartKubeletFileContent

<#
Write-Host "Installing nssm"
$arch = "win32"
if ([Environment]::Is64BitOperatingSystem) {
    $arch = "win64"
}

mkdir -Force $global:NssmInstallDirectory
DownloadFile nssm.zip https://k8stestinfrabinaries.blob.core.windows.net/nssm-mirror/nssm-2.24.zip
tar C $global:NssmInstallDirectory -xvf .\nssm.zip --strip-components 2 */$arch/*.exe
Remove-Item -Force .\nssm.zip

$env:path += ";$global:NssmInstallDirectory"
$newPath = "$global:NssmInstallDirectory;" +
[Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)

[Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)

Write-Host "Registering kubelet service"
nssm install kubelet $global:Powershell $global:PowershellArgs $global:StartKubeletScript
#nssm set kubelet DependOnService containerd

#>

New-NetFirewallRule -Name kubelet -DisplayName 'kubelet' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 10250
