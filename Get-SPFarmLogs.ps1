######################################################################################################

        #        This script is intended to gather farm logs                                 #

        #        it will get logs from ULS , IIS based on date and EventViewer Application   #

        #        and System.                                                                 #

	    #        Version 3.0                                                                 #

        #        provided by Miguel Godinho / Sharepoint SEE at Microsoft Support 06/01/2017 #

		# 		 last modification : 04/may/2021                                    	     #

######################################################################################################

<#
example
get-spfarmlogs -user contoso\administrator `
-server "server1,server2,server3"
-eventsdir "C:\collectfarmlogs\logs" `
-IISdate yymmdd `
-ULSstarttime "20/jan/2019 19:30" `
-ULSendtime "20/jan/2019 21:30" `
-noevents $true or $false
.\Get-SPFarmLogs.ps1 -EventsDir C:\myfold\logfold -ULSstarttime "20/jan/2019 19:30" -ULSendtime "20/jan/2019 21:30" -NoEvents $false -IISdate 190120
#>

param (
	[Parameter(Mandatory=$false)]
    [string]
    $NoEvents=$false
    ,
    [parameter(Mandatory=$false)]
    [string] 
    $user=""
    ,
    [Parameter(Mandatory=$true)]
    [string] 
    $EventsDir=""
    ,
    [Parameter(Mandatory=$false)]
    [string]
    $IISdate=$null
    , 
    [Parameter(Mandatory=$false)]
    [datetime]
    $ULSstarttime 
    ,
    [Parameter(Mandatory=$false)]
    [datetime]
    $ULSendtime
	,
    [Parameter(Mandatory=$false)]
    [string]
    $servers=""
)
# monitor log
$loggingfile = $EventsDir +"\loggingfile.log"

function logmig($event){
	"[$(Get-Date)]$event"| out-file $loggingfile -append;	
}
# load necessary modules
try{
# load SharePoint Module
if(-not(Get-PSSnapin | Where { $_.Name -eq "Microsoft.SharePoint.PowerShell"}))
{
    Add-PSSnapin Microsoft.SharePoint.Powershell -ea 0
    Start-SPAssignment -Global   
}
else{"";}#Start-SPAssignment -Global}
# load IIS module
Import-Module webadministration
}
catch{
	$Error[0].Exception.Message
}

# variables
$spDiag = get-spdiagnosticconfig
$global:ulsPath = $spDiag.LogLocation
$global:LogCutInterval = $spDiag.LogCutInterval

# folders 
$defLogPath = $ulsPath -replace "%CommonProgramFiles%", "C$\Program Files\Common Files"
$defLogPath= $defLogPath.replace(':','$');
Write-Host("ULS logs are at \\server\" + $defLogPath);

function GetEventsLogs([string]$server,[Management.Automation.PSCredential]$credential,$EventType)
{
    $h.ForegroundColor="yellow"
	write-host"";
	Write-Host("Getting $EventType logs from $server");
    $h.ForegroundColor="gray"
    try {
		if($credential -and $server -ne "$env:COMPUTERNAME" ){
			return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server -credential $credential | where {$_.logfilename -eq "$EventType"}
        }

		else{
			return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server | where {$_.logfilename -eq $EventType}
		}

        if($credential -and $server -eq "$env:COMPUTERNAME" ){
			return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server | where {$_.logfilename -eq $EventType}
        }	
    }
    catch{
        # we don't know how it fails then we will try with network access
        $h.ForegroundColor="red"
        "$Error[0].Exception.Message"
        $path = "\\$server\c$\WINDOWS\system32\winevt\Logs\" + $EventType + ".evtx"
        return Get-ChildItem $path 
    }
}
function GetIISlogs ([string]$server, [Management.Automation.PSCredential]$credential)
{
    $h.ForegroundColor="yellow";
    Write-Host("Getting IIS logs from $server") -ForegroundColor Green;
	logmig ("Getting IIS logs from $server")
    try{

			# we need to use [ADSI] access for reading the ApplicationHost.config
			# check the default location
			$sites=$null
            try{
            [xml]$web=get-content "\\$server\admin$\system32\inetsrv\config\applicationhost.config"
			logmig "\\$server\admin$\system32\inetsrv\config\applicationhost.config" ;
			$deffold=$null;
			$logfile =($web.configuration."system.applicationHost".sites.siteDefaults.logFile.directory)
			$deffold = $logfile -replace "%SystemDrive%","$env:SystemDrive";
			$sites =($web.configuration."system.applicationHost".sites)
			$allIISnodes = $sites.ChildNodes
			# getting the default IIS logs location
			write-verbose $deffold
			$iispath = @{};
			$allIISnodes = $allIISnodes | ?{$_.id}
            $iismapfile = ("{0}\{1}_{2}" -f $IISfolder, $server, "_iismapping.txt");
            $null | Out-File $iismapfile -Force
            foreach($node in $allIISnodes){
                "----//----"
                "processing " + $node.name;
                $node.name + " -----> " + $node.id + " -----> " + $node.bindings.binding.protocol +" ---> " + $node.bindings.binding.bindingInformation | Out-File $iismapfile -Append
				$foldFormat =  "W3SVC" + $node.id;                
                if($node.logFile.directory -eq $null){
					$ttemp = $deffold.replace(":","$");                    
				}
                else{
                $ttemp= $node.logFile.directory;
                write-verbose $ttemp                                                        
                }
				$iisNTpath = "\\$server\" + $ttemp + "\" +$foldFormat;
                write-verbose "processing $iisNTpath";
                logmig("processing $iisNTpath");
                if(Test-Path -Path $iisNTpath){
					$files = get-childItem -Path $iisNTpath -Filter "*$IISdate*.log" ;
                    logmig("there is " + $files.count + " IIS's logs to process");
                    if($files.count -gt 0){
					    ""
                        #$destf = ("{0}\{1}_{2}\{3}" -f $srvfolderIIS, "IIS", $server, $foldFormat);
                        $destf = ("{0}\{1}_{2}" -f $srvfolderIIS, $server, $foldFormat);
					    #Create the destination folder with W3SVC and site ID
                        New-Item -Path $destf -Force -ItemType:directory| Out-Null;
					    Write-Host $destf
					    logmig $destf                                    
					    try{
						    if(Test-Path -Path $destf){
							    foreach($fichier in $files){
								$renamefile = "$server" + "_"  + $fichier.Name
                                Write-Verbose "copying the file $fichier.name"
                                $destination = ("{0}\{1}" -f $destf,$renamefile)
                                Write-Verbose $destination 
								Copy-Item $fichier.FullName -Destination $destination -Force -Container:$false;
								logmig($fichier.fullname + " -- " + $destination)
							    }
						    }
                        }
					    catch{ $Error[0].Exception.Message}
						Start-Sleep 2;
						$h.ForegroundColor="green";
						$sname = $node.name;
						Write-Host "done for site $sname ";
                        logmig("done for site $sname ");
						Write-Host "-------//-------";
						write-host"";
					}
					else{
                    $sname = $node.name
					Write-Host "no entries for site $sname" -ForegroundColor Red;
					Write-Host "-------//-------";
                    write-host"";
					}
                }
                else{
                    $sname = $node.name
					Write-Host "no entries for site $sname" -ForegroundColor Red;
					Write-Host "-------//-------";
                    write-host"";
                }
			}
			} 
            catch{
			$Error[0].exception.Message
			logmig("$Error[0].Exception.Message")
			}
    }
    catch{
      $h.ForegroundColor="red"
      $Error[0].Exception.Message
	  logmig("$Error[0].Exception.Message")
      Remove-PSSession -Session $Session
    }               
}
function SplitAllUls($server){
    # location to save the files based on the Server name
    Write-Verbose("logs will be saved in $srvfolder");
    $srvfolder = $EventsDir+"\"+$server;
    Write-Host("Gettings ULS logs from $server ...") -ForegroundColor darkYellow
    $sourceFold = "\\" + $server + "\" + $defLogPath
	write-verbose $sourceFold
    if(Test-Path -Path $sourceFold){
		"-------------"
        write-host("Getting ready to copy logs from: " + $sourceFold);
        logmig("Getting ready to copy logs from: " + $sourceFold);
		#subtracting the 'LogCutInterval' value to ensure that we grab enough ULS data 
		$sTime=$ULSstarttime.AddMinutes(-$LogCutInterval)
		# setting the endTime variable # removed since we force $ulsendtiem to be DateTime type
		$specfiles = get-childitem -path $sourceFold | ?{$_.Extension -eq ".log" -and ($_.Name) -like "$server*" -and $_.CreationTime -lt $ULSendtime -and $_.CreationTime -ge $sTime}  | select Name, CreationTime
		if($specfiles.Length -eq 0){
			write-host(" We did not find any ULS logs for server, " + $server +  ", within the given time range")
			logmig(" We did not find any ULS logs for server, " + $server +  ", within the given time range")
		}
		foreach($file in $specfiles){
			$filename = $file.name
            Write-host("Copying file:  " + $filename) -ForegroundColor Green;
			logmig("Copying file:  " + $filename) -ForegroundColor Green;
            $srvfolderULS
            copy-item "$sourceFold\$filename" $srvfolderULS -Force
		}     
	}
    else{
        write-host("On the server $server, ") -BackgroundColor DarkRed; 
		write-host("the folder c:" + $sourceFold.split('$')[1] + " doesn't exist") -BackgroundColor DarkRed; 
		"------//------"
    }
}

################################
#        main program          #
################################

new-Item -Path $eventsdir -Force -ItemType:directory| Out-Null;
# creating folders for each type of logs 
$Eventfolder = new-Item -Path "$eventsdir\Events" -Force -ItemType:directory;
$IISfolder = new-Item -Path "$eventsdir\IIS" -Force -ItemType:directory;
$ULSfolder = new-Item -Path "$eventsdir\ULS" -Force -ItemType:directory;

write-host("creating folders for each type of logs: ");
$iisfolder
$ULSfolder
$Eventfolder
<##>
$null | Out-File $loggingfile -force
logmig "starting logging"
logmig $defLogPath;
$Error.Clear();
$h=(Get-Host).UI.RawUI
$h.ForegroundColor="DarkYellow"
write-host("There is a syntax example");
write-host('.\Get-SPFarmLogs.ps1 -EventsDir C:\myfold\logfold -ULSstarttime "20/jan/2019 19:30" -ULSendtime "20/jan/2019 21:30" -NoEvents $false -IISdate 190120');
$h.BackgroundColor="black"
$h.ForegroundColor="green"
if($user){
	$password =  read-host "Provide the password for the Admin Remote Servers " -AsSecureString ;
	$credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $password
	$h.ForegroundColor="gray"
}

# handle servers to be processed
$srvs="";
if(!$servers -or ($servers -eq $null)){
   $srvs= get-spserver | ?{$_.Role -ne "Invalid"} | % {$_.Address};   
}
else{
    $srvs = $servers.split(',');
}
try{
    if($srvs -or $srvs -eq ""){   	
		foreach($server in $srvs){	
		Write-Host("-------//-------") -ForegroundColor Magenta;
		write-host("Processing the server: $server") -ForegroundColor Magenta ;
		logmig("Processing the server: $server")

		#check if server is available to PING or fileshare access

		if(!((Test-Connection -Quiet $server -Count 2) -or (Test-Path "\\$server\c$"))) {

			write-host("[$server] connection or server not available") -ForegroundColor Red;
			logmig("[$server] connection or server not available")

		}

		else{
			#creating the folder for the server's logs
			$srvfolderEvents = $Eventfolder.fullname + "\" + $server
			$srvfolderIIS = $IISfolder.fullname + "\"+ $server
			$srvfolderULS = $ULSfolder.fullname + "\"+ $server
			# display folders used 
			$srvfolderEvents
			$srvfolderIIS
			$srvfolderULS
			
			logmig("creating folder $srvfolderEvents")
            ""
            logmig("creating folder $srvfolderIIS")
            ""
            logmig("creating folder $srvfolderULS")
			
			try{				
			# create's a server name folder in the 3 categories Event,IIS and ULS
			new-Item -Path $srvfolderEvents -Force -ItemType:directory| Out-Null;
			new-Item -Path $srvfolderIIS -Force -ItemType:directory| Out-Null;
			new-Item -Path $srvfolderULS -Force -ItemType:directory| Out-Null;
			}
			catch{  
			throw "$Error[0].Exception.Message"
			logmig("$Error[0].Exception.Message")
			return  
			}
			$h.ForegroundColor="green"
			try{

				if($NoEvents -eq $false){
				# get Application and System Event viewer
				$EventsType = "Application","System";

					foreach($EvType in $EventsType){

					logmig("getting event viewer $EvType")
					$events = GetEventsLogs -server $server -credential $credential -EventType $EvType;
					[string]$src01 = ("\\{0}\{1}" -f $server, $events.name) -replace ":\\", "$\";
					$h.ForegroundColor="gray";
					$destEvType = ("{0}\{1}_{2}.evtx" -f $srvfolderEvents, $EvType, $server);
					if($credential){

						 $remfolder = Split-Path -parent $src01
						 if(!(Test-Path -Path v:)){
						 New-PSDrive -Name v -PSProvider filesystem -Root $remfolder  -Credential $credential -Scope local 
						 } 
						 Copy-Item -Path "v:\$EvType.evtx" -Destination $destEvType -Force ;
					}
					else{
						Copy-Item -Path $src01 -Destination $destEvType -Force
					}

					Write-Host("-------//-------");
					}	
				}

			 #  Processing IIS logs
			 if($IISdate){
				
				logmig("processing IIS logs for $server start")
				GetIISlogs -server $server -credential $credential;
				logmig("processing IIS logs for $server end")

			 }
			 else{Write-Host("-------//-------");}
			 if($ULSstarttime -and $ULSendtime){
				
				logmig("getting ULS logs started now...")
				SplitAllUls($server);
				logmig("getting ULS logs finished now...")

			 }
			}        
			catch{throw "$Error[0].Exception.Message"
			logmig("$Error[0].Exception.Message")
			}
		}
		}
    }
    else{
	    write-host("Unexpected situation, there is no targeted server"); 
        logmig("Unexpected situation, there is no targeted server");
	    write-host("you can define the switch -servers ""server1,server2,server3"" to be sure that the script can be run"); 
        logmig("you can define the switch -servers ""server1,server2,server3"" to be sure that the script can be run"); 
    }
}
catch{
	$errormessage = $_.Exception.Message
	write-Verbose "An error occurred: $errormessage"
    logmig("An error occurred: $errormessage");
}

# ZIP area 
if($ULSendtime){
$filetag = ($ULSendtime).ToString("yyMMdd-HHmm");
}
else{$filetag = (Get-Date).ToString("yyMMdd-HHmm");}
""
Write-Host("Compressing result files to MSLogs_$($filetag).zip") -ForegroundColor Green
""
Write-Host("depending the size of the folder it might take a while, please be patient.") -ForegroundColor Cyan

Add-Type -assembly "system.io.compression.filesystem"
$destinationZip = (get-item $EventsDir ).Parent.FullName + "\MSLogs_$($filetag).zip"
""
if(!(Test-Path $destinationZip)){

$CompressionToUse = [System.IO.Compression.CompressionLevel]::Optimal
[System.IO.Compression.ZipFile]::CreateFromDirectory($EventsDir,$destinationZip,$CompressionToUse,$false)
}
else{
    Write-Host("File $destinationZip already exist, it hasn't been zipped again, you have to check it manually") -ForegroundColor Red
}

if(-not(Get-PSSnapin | Where { $_.Name -eq "Microsoft.SharePoint.PowerShell"}))
{
    Stop-SPAssignment -Global    
}

$h.ForegroundColor="white";   
"";
Write-Host "script ended..."
logmig( "script ended...")


