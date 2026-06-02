param (
    [string]$minK8sVersion = "v1.22"
)

function Get-K8sVersionCore($tag) {
    $tagMatch = [regex]::Match($tag, "^v?(?<version>\d+\.\d+(?:\.\d+)?(?:\.\d+)?)(?:-.+)?$")
    if (-not $tagMatch.Success) {
        return $null
    }

    return [Version]$tagMatch.Groups["version"].Value
}

# Get kube-proxy images
$content = curl.exe -L registry.k8s.io/v2/kube-proxy/tags/list
$json = ConvertFrom-Json $content

$minVersion = Get-K8sVersionCore $minK8sVersion
if ($null -eq $minVersion) {
    Write-Error "Invalid minimum Kubernetes version: $minK8sVersion"
    exit 1
}

$missingKubeProxyImages = @()

foreach ($tag in $json.tags) {
    if (-not($tag.StartsWith("v"))) {
        continue
    }

    $tagVersion = Get-K8sVersionCore $tag
    if ($null -eq $tagVersion) {
        continue
    }
    if ($tagVersion -lt $minVersion) {
        continue
    }

    foreach ($flavor in @("-calico-hostprocess")) {
        $image = "sigwindowstools/kube-proxy:$tag$flavor"
        Write-Output "Checking for image $image"
        docker manifest inspect $image | Out-Null
        if ($LastExitCode -ne 0) {
            $missingKubeProxyImages += $image
            Write-Output "  Image $image is missing!"
        }
    }
}

if ($missingKubeProxyImages.Length -gt 0) {
    Write-Output "Found $($missingKubeProxyImages.Length) missing images!"
    exit 1
}
