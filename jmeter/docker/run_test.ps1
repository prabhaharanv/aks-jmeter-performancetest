param(
    [Parameter(Mandatory=$true)]
    [string]
    $tenant,
    # Name of test
    [Parameter(Mandatory=$true)]
    [string]
    $TestName,
    # Where to put the report directory
    [Parameter(Mandatory=$true)]
    [string]
    $ReportFolder,
    [Parameter(Mandatory=$false)]
    [bool]
    $DeleteTestRig = $true,
    [Parameter(Mandatory=$false)]
    [string]
    $UserProperties="",
    [Parameter(Mandatory=$false)]
    [string]
    $RedisScript="",
    [parameter(ValueFromRemainingArguments=$true)]
    [string[]]
    $GlobalJmeterParams
)
$CurrentPath = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location $CurrentPath
if($null -eq $(kubectl -n $tenant get pods --selector=jmeter_mode=master --no-headers=true --output=name) )
{
    Write-Error "Master pod does not exist"
    exit
}
$MasterPod = $(kubectl -n $tenant get pods --selector=jmeter_mode=master --no-headers=true --output=name).Replace("pod/","")

$SlavePods = $(kubectl -n $tenant get pods --selector=jmeter_mode=slave --no-headers=true --output=name).Replace("pod/","")
foreach ($SlavePod in $SlavePods)
{
	Write-Output "Copying test data files from local TestData folder to ${SlavePod}"
	kubectl cp TestData/ $tenant/${SlavePod}:/
}

Write-Output "Checking for user properties"
if(!($UserProperties -eq $null -or $UserProperties -eq "" ))
{
    Write-Output "Copying user.properties over"
    kubectl cp $UserProperties $tenant/${MasterPod}:/jmeter/apache-jmeter-5.1.1/bin/user.properties
}
Write-Output "Checking for Redis script"
if(!($RedisScript -eq $null -or $RedisScript -eq ""))
{
    #Since we use helm to install Redis we can assume the pod name for the first redis slave instance
    write-output "Executing redis script"
    Get-Content $RedisScript | kubectl -n $tenant exec -i redis-release-master-0 -- redis-cli --pipe
}
Write-Output "Processing global parameters"
[string]$GlobalParmsCombined=" "
foreach($gr in $GlobalJmeterParams)
{
    $GlobalParmsCombined += $gr + " "

}
Write-Output "Copying test plan to aks"
kubectl cp $TestName $tenant/${MasterPod}:"/$(Split-Path $TestName -Leaf)"
Write-Output "Starting test execution on AKS Cluster"
kubectl -n $tenant exec $MasterPod -- /load_test_run "/$(Split-Path $TestName -Leaf)" $GlobalJmeterParams
Write-Output "Retrieving dashboard, results and Master jmeter.log"
kubectl cp $tenant/${MasterPod}:/report $ReportFolder
kubectl cp $tenant/${MasterPod}:/results.log $ReportFolder/results.log
kubectl cp $tenant/${MasterPod}:/jmeter/apache-jmeter-5.1.1/bin/jmeter.log $ReportFolder/jmeter.log
if($DeleteTestRig)
{
	Write-Output "Removing JMeter master and slave pods"
    kubectl -n $tenant delete -f jmeter_master_deploy.yaml
    #Write-Output "Copying test data files from ${MasterPod} to local"
	#kubectl cp $tenant/${MasterPod}:/TestDataRun TestDataFrom_${MasterPod}/
	foreach ($SlavePod in $SlavePods)
	{
		Write-Output "Copying test data files from ${SlavePod} to local"
		#kubectl cp $tenant/${SlavePod}:/TestDataRun TestDataFrom_$SlavePod/
		kubectl cp $tenant/${SlavePod}:/TestDataRun/datafile1.csv TestDataFrom_$SlavePod/
		kubectl cp $tenant/${SlavePod}:/TestDataRun/datafile2.csv TestDataFrom_$SlavePod/
	}
	
	kubectl -n $tenant delete -f jmeter_slaves_deploy.yaml
    #helm del --purge redis-release
}