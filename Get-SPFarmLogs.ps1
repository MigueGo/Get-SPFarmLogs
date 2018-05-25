
######################################################################################################
        #        This script is intended to gather farm logs                                 #
        #        it will get logs from ULS , IIS based on date and EventViewer Application   #
        #        and System.                                                                 #
	    #        Version 3.0                                                                 #
        #        provided by Miguel Godinho / Sharepoint SEE at Microsoft Support 06/01/2017 #
		# 		 last modification : 09/03/2018                                      	     #
######################################################################################################
<#
example
get-spfarmlogs -user contoso\administrator `
-server "server1,server2,server3"
-eventsdir "C:\collectfarmlogs\logs" `
-IISdate yymmdd `
-ULSstarttime "06/30/20xx 18:30" `
-ULSendtime "06/30/20xx 19:30" `
-noevents $true or $false

.\Get-SPFarmLogs.ps1 -EventsDir C:\myfold\logfold -ULSstarttime "02/20/2018 19:30" -ULSendtime "02/20/2018 21:30" -NoEvents $false -IISdate 180225
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
    [string]
    $ULSstarttime="" 
    ,
    [Parameter(Mandatory=$false)]
    [string]
    $ULSendtime=""
	,
    [Parameter(Mandatory=$false)]
    [string]
    $servers=""
    
)


# load necessary modules
try{
# load SharePoint Module
if(-not(Get-PSSnapin | Where { $_.Name -eq "Microsoft.SharePoint.PowerShell"}))
{Add-PSSnapin Microsoft.SharePoint.Powershell -ea 0}
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
Start-SPAssignment -Global

# folders 
$defLogPath = (get-spdiagnosticconfig).LogLocation -replace "%CommonProgramFiles%", "C$\Program Files\Common Files"
$defLogPath = $defLogPath -replace ":", "$";
Write-Verbose("$defLogPath");


function GetEventsLogs([string]$server,[Management.Automation.PSCredential]$credential,$EventType)
{
    $h.ForegroundColor="yellow"
	write-host"";
    Write-Host("Getting $EventType logs from $server")
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
    try{
		# we need to check if remote PowerShell is possible to the remote server
        $Session=$null;
        try{
			Write-Verbose -ForegroundColor White " - Enabling WSManCredSSP for `"$server`""
            Enable-WSManCredSSP -Role Client -Force -DelegateComputer $server | Out-Null ;
            $Session = New-PSSession -ComputerName $server -ea 0 
            # only retrive the data really need to avoid to exceed the buffer 
        }
        catch{
			Write-Verbose("we are not able to use PS remote session");
        }
        Write-Verbose "before testing session"
        Write-Verbose "$session"
        if($session){
			$block = { 
			Import-Module 'webAdministration' -ErrorAction 0;
			get-website | %{($_.name + ";" + $_.id + ";" +  $_.logFile.directory)}
			}
			$rsites = Invoke-Command -Session $Session -ScriptBlock $block; 
			foreach($WebSite in $rsites){
				$line = $WebSite.split(';');
				$logFilefolder="$($line[2])\W3SVC$($line[1])".replace("%SystemDrive%",$env:SystemDrive)
				$netfolder = Split-Path -Path $logFilefolder -noQualifier;
				$folder =Split-Path -Path $logFilefolder -Leaf;
				$sourcepath = ("\\" + ($server + "\C$" + $netfolder));
				$files = get-childItem -Path $sourcepath -Recurse -Filter "*$IISdate*.log" ;
				if((Test-Path -Path $sourcepath) -and ($files.count -gt 0)){
					$destf = ("{0}\{1}_{2}\{3}" -f $srvfolder, "IIS", $server, $folder);
					#Create the destination folder with W3SVC and site ID
					New-Item -Path $destf -Force -ItemType:directory| Out-Null;
					try{
					if(Test-Path -Path $destf){
						foreach($fichier in $files){
							Copy-Item $fichier.FullName -Destination $destf -Force -Container:$false;
					}}}
					catch{$Error[0].Exception.Message}
					Start-Sleep 2;
					$h.ForegroundColor="green";					
					Write-Host( " done for site " + ($line[0]).ToString());
					Write-Host("------//------");
                    
					$h.ForegroundColor="green";                                               
				}
				else{
					$h.ForegroundColor="magenta";
					
					Write-Host(" no entries for the site " + $line[0]);
					Write-Host("-------//-------");
                    write-host"";
				}
			}
			$h.ForegroundColor="green";
			Write-Host( "... end server $server");
			Write-Host("-------//-------") -ForegroundColor "blue";
			$h.ForegroundColor="green";
			Remove-PSSession -Session $Session
		}
		else{ 
			
			#since the WinRM is failing we need to use [ADSI] access or reading the ApplicationHost.config
			#check the default location
			# if there is no files prompt user to specify the IIS logs folder
			$sites=$null
            try{
            [xml]$web=get-content "\\$server\admin$\system32\inetsrv\config\applicationhost.config"
			$deffold=$null;
			
			$logfile =($web.configuration."system.applicationHost".sites.siteDefaults.logFile.directory)
			$deffold = $logfile -replace "%SystemDrive%","$env:SystemDrive";
			
			$sites =($web.configuration."system.applicationHost".sites)
			$allnodes = $sites.ChildNodes
			# getting the default IIS logs location
			write-verbose $deffold
			$iispath = @{};
			$allnodes = $allnodes | ?{$_.id}
			foreach($node in $allnodes){
				
                $node.name
                ""
                $foldFormat =  "W3SVC" + $node.id;                
                if($node.logFile.directory -eq $null){
					$ttemp = $deffold.replace(":","$");                    
				}
                else{
                $ttemp= $node.logFile.directory;
                write-verbose $ttemp                                                        
                }
				$iisNTpath = "\\$server\" + $ttemp + "\" +$foldFormat;
                write-verbose $iisNTpath
                if(Test-Path -Path $iisNTpath){
					$files = get-childItem -Path $iisNTpath -Filter "*$IISdate*.log" ;
                    if($files.count -gt 0){
					    $destf = ("{0}\{1}_{2}\{3}" -f $srvfolder, "IIS", $server, $foldFormat);
					    #Create the destination folder with W3SVC and site ID
                        New-Item -Path $destf -Force -ItemType:directory| Out-Null;
					    Write-Host $destf
					    try{
						    if(Test-Path -Path $destf){
							    foreach($fichier in $files){
								    $fchfull = $fichier.FullName;
								    Copy-Item $fichier.FullName -Destination $destf -Force -Container:$false;
							    }
						    }
                        }
					    catch{ $Error[0].Exception.Message}
					Start-Sleep 2;
					$h.ForegroundColor="green";
                    $sname = $node.name;
                    Write-Host "done for site $sname ";
					Write-Host "-------//-------";
                    write-host"";
					}
					else{
                    $sname = $node.name
					Write-Host "no entries for site $sname" -ForegroundColor Red;
					Write-Host "-------//-------";
                    write-host"";
					}
                                                                            
                }#if ln 224
                else{
                    $sname = $node.name
					
					Write-Host "no entries for site $sname" -ForegroundColor Red;
					Write-Host "-------//-------";
                    write-host"";
                }
							
			}
			} 
            catch{$Error[0].exception.Message}
		}
    }
    catch{
      $h.ForegroundColor="red"
      $Error[0].Exception.Message
      Remove-PSSession -Session $Session
    }               
}

function SplitAllUls($server)
 {
    # location to save the files based on the Server name
    Write-Verbose("logs will be saved in $srvfolder");
    $srvfolder = $EventsDir+"\"+$server;
    Write-Host("Gettings ULS logs from $server ...") -ForegroundColor darkYellow
    $defLogPath = $defLogPath -replace ":", "$"
    $sourceFold = "\\" + $server + "\" + $defLogPath
	write-verbose $sourceFold
    if(Test-Path -Path $sourceFold){
		"-------------"
        "Getting ready to copy logs from: " + $sourceFold
		""
		# subtracting the 'LogCutInterval' value to ensure that we grab enough ULS data 
		$ULSstarttime = $ULSstarttime.Replace('"', "")
		$ULSstarttime = $ULSstarttime.Replace("'", "")
		$sTime = (Get-Date $ULSstarttime).AddMinutes(-$LogCutInterval)

		# setting the endTime variable
		$ULSendtime = $ULSendtime.Replace('"', "");
		$ULSendtime = $ULSendtime.Replace("'", "");
		$eTime = Get-Date $ULSendtime;
		
		$specfiles = get-childitem -path $sourceFold | ?{$_.Extension -eq ".log" -and ($_.Name) -like "$server*" -and $_.CreationTime -lt $eTime -and $_.CreationTime -ge $sTime}  | select Name, CreationTime
		if($specfiles.Length -eq 0)
		{
			" We did not find any ULS logs for server, " + $server +  ", within the given time range"
		}
		foreach($file in $specfiles)
			{
				$filename = $file.name
                Write-host("Copying file:  " + $filename) -ForegroundColor Green;
				copy-item "$sourceFold\$filename" $srvfolder -Force
			}     
	}
    else{
        write-host("On the server $server, ") -BackgroundColor DarkRed; 
        write-host("the folder c:" + $sourceFold.split('$')[1] + " doesn't exist") -BackgroundColor DarkRed; 
        "------//------"
    }
 }

#################################################

#main
#function Get-SPFarmLogs(){}

$Error.Clear();
$h=(Get-Host).UI.RawUI
$h.ForegroundColor="DarkYellow"

write-host("There is a syntax example");
write-host('.\Get-SPFarmLogs.ps1 -EventsDir C:\myfold\logfold -ULSstarttime "02/20/2018 19:30" -ULSendtime "02/20/2018 21:30" -NoEvents $false -IISdate 180225');

$h.BackgroundColor="black"
$h.ForegroundColor="green"

if($user){
$password =  read-host "Provide the password for the Admin Remote Servers " -AsSecureString ;
$credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $password
$h.ForegroundColor="gray"
}
$srvs=$null;

if(!$servers -or ($servers -eq $null)){
    $srvtemp= Get-SPServer | ?{$_.role -ne "Invalid"} ;
    $srvs = $srvtemp | select address -ExpandProperty address;
}
else{
    $srvs = $servers.split(',');
}
    
foreach($server in $srvs){

	Write-Host("-------//-------") -ForegroundColor Magenta;
    write-host("Processing the server: $server") -ForegroundColor Magenta ;
    #check if server is available to PING or fileshare access
	if(!((Test-Connection -Quiet $server -Count 2) -or (Test-Path "\\$server\c$"))) {
		write-host("[$server] connection or server not available") -ForegroundColor Red;
    }
    else{
        #creating the folder for the server's logs
	    $srvfolder = $EventsDir+"\"+$server
	    try{
        new-Item -Path $srvfolder -Force -ItemType:directory| Out-Null;
        }
        catch{      
        throw "$Error[0].Exception.Message"
        return    
        }
        $h.ForegroundColor="green"
        try{
			if($NoEvents -eq $false){
			
            # get Application and System Event viewer
            $EventsType = "Application","System";
            foreach($EvType in $EventsType){
            $events = GetEventsLogs -server $server -credential $credential -EventType $EvType;
            [string]$src01 = ("\\{0}\{1}" -f $server, $events.name) -replace ":\\", "$\";
            $h.ForegroundColor="gray";
            $destEvType = ("{0}\{1}_{2}.evtx" -f $srvfolder, $EvType, $server);
            Copy-Item -Path $src01 -Destination $destEvType -Force;
            Write-Host("-------//-------");
            }
                    }
         #  Processing IIS logs
         if($IISdate){
			GetIISlogs -server $server -credential $credential
            }
         else{Write-Host("-------//-------");}

         if($ULSstarttime -and $ULSendtime){
			SplitAllUls($server);
		 }
		}        
        catch{throw "$Error[0].Exception.Message"}
	}
}

$h.BackgroundColor="black";
$h.ForegroundColor="white";   
write-host"";
Write-Host "script ended..."
