#Lazy and ripped this function from https://stackoverflow.com/questions/11412617/get-a-folder-path-from-the-explorer-menu-to-a-powershell-variable
Function Select-FolderDialog
{
    param(
    [string]$Description,
    [string]$RootFolder="Desktop"
    )

 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
     Out-Null     

   $objForm = New-Object System.Windows.Forms.FolderBrowserDialog
        $objForm.Rootfolder = $RootFolder
        $objForm.Description = $Description
        $Show = $objForm.ShowDialog()
        If ($Show -eq "OK")
        {
            Return $objForm.SelectedPath
        }
        Else
        {
            Write-Error "Operation cancelled by user."
        }
    }


$syncHash = [HashTable]::Synchronized(@{})
$syncHash["scriptBlocks"] = @{}
$syncHash["paths"] = @{}
$syncHash["pools"] = [System.Collections.ArrayList]::new()
$syncHash["threads"] = [System.Collections.ArrayList]::new()

#Call function to get all paths
<#
$syncHash["paths"]["ffmpegPath"] = Select-FolderDialog -Description "Navigate to ffmpeg path"
$syncHash["paths"]["inputvideo"] = Select-FolderDialog -Description "Select video root folder that you want to redux from FLV"
$syncHash["paths"]["outputPath"] =  Select-FolderDialog -Description "Select video root folder that you want to redux to from FLV to MP4"
$syncHash["paths"]["files"] = Get-ChildItem -Path $syncHash["paths"]["inputvideo"] | Select-Object FullName
#>
$syncHash["paths"]["ffmpegPath"] = "D:\ffmpeg\bin"
$syncHash["paths"]["inputvideo"] = "G:\twitchClipz"
$syncHash["paths"]["outputPath"] =  "G:\twitchClipzRemux"
$syncHash["paths"]["files"] = Get-ChildItem -Path $syncHash["paths"]["inputvideo"] | Select-Object FullName

#Scriptblock Storage
$reduxFLVtoMP4SB = {
    param(
        [int]$i
    )
    Start-Transcript -Path "C:\TEMP\logs\$($i).log"
    echo $syncHash
    $file = ($syncHash["paths"]["files"][$i]).FullName
    $outputFileName = $syncHash["paths"]["outputPath"] + '\' + (($($file) | Split-Path -Leaf).Replace('.flv', '.mp4'))
    Set-Location -Path $syncHash["paths"]["ffmpegPath"]
    ./ffmpeg.exe -i $($file) -c copy $($outputFileName)
    Stop-Transcript
}

$syncHash["scriptBlocks"]["reduxFLVtoMP4SB"] = $reduxFLVtoMP4SB

#Create pools and pass initial params
$syncHashPass = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'syncHash',$syncHash,$null
$initSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initSessionState.ApartmentState = "MTA"
$initSessionState.Variables.Add($syncHashPass)

$syncHash["pools"].Add(([RunspaceFactory]::CreateRunspacePool(1, ($syncHash["paths"]["files"].Count), $initSessionState, $host)))
$syncHash["pools"].Open()


$i = 0
foreach ($file in $syncHash["paths"]["files"]) {
    $params = New-Object System.Collections.Generic.Dictionary"[String,int]"
    $params.Add('i', $i)
    $ffmpegPSObject = [Powershell]::Create()
    $ffmpegPSObject.RunspacePool = $syncHash["pools"][0]
    [void]($ffmpegPSObject.AddScript($syncHash["scriptBlocks"]["reduxFLVtoMP4SB"]).AddParameters($params))
    [void]($syncHash["threads"].Add((
        [PSCustomObject]@{
            Runspace = $ffmpegPSObject.BeginInvoke()
            Powershell = $ffmpegPSObject
        }
    )))
    $i++
}

#Loop to montior threads and nuke when they flip to available/complete status.
$tasks = $syncHash["threads"].Runspace
$totalTasks = $tasks.IsCompleted.Count
$iComplete = 0
while ($tasks.IsCompleted -contains $false) {
    $iComplete = ($tasks.IsCompleted | Where-Object {$_ -eq "True"}).Count
    Write-Progress -Activity "Processing via FFMPEG" -Status "Processed: $($iComplete) of $($totalTasks)" -PercentComplete (($iComplete / $totalTasks) * 100)
    Start-Sleep 1
}
Write-Progress -Activity "Processing via FFMPEG" -Status "Ready" -Completed
