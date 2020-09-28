Param(
    [parameter(HelpMessage="Name of network adapter")]
    [string] $AdapterName = "Ethernet"
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
