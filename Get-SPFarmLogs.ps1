######################################################################################################
        #        This script is entended to gather farm logs                                 #
        #        it will get logs from ULS , IIS based on date and EventViewer Application   #
        #        and System.                                                                 #
		#        Version 2.0                                                                 #
        #        provided by Miguel Godinho / Sharepoint SEE at Microsoft Support 06/01/2017 #
		# 		 last modification : 10/01/2017                                              #
######################################################################################################
<#
example
.\get-spfarmlogs.ps1 -user contoso\admincc -eventsdir "C:\collectfarmlogs\logs" -IISdate 160916 -ULSstarttime "06/30/20xx 18:30" -ULSendtime "06/30/20xx 19:30"

working date 
01/04/2017 16:00



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
    [Parameter(Mandatory=$false)]
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
{
    Add-PSSnapin Microsoft.SharePoint.Powershell -ea 0
}
# load IIS module
Import-Module webadministration

}
catch{
	$Error[0].Exception.Message
}


function GetEventsLogsApplication ([string]$server,[Management.Automation.PSCredential]$credential)
{
                $h.ForegroundColor="yellow"
                Write-Host("Getting Application logs from $server")
                $h.ForegroundColor="gray"
                if(!(Test-Connection -Quiet $server -Count 5)) {
                               throw "[$server] connection not available"
                }
                try {
                               
                               if ($server -eq $env:COMPUTERNAME) {
                                               return Get-WmiObject -Class:Win32_NTEventlogFile | where {$_.logfilename -eq "application"}
                               }

                               return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server -credential $credential | where {$_.logfilename -eq "application"}
                               }
                catch {
                               throw "[GetEventsLogsApplication][$server] (Ligne $($_.InvocationInfo.ScriptLineNumber)) $_"
                }
}

function GetEventsLogsSystem ([string]$server, [Management.Automation.PSCredential]$credential)
{
                
                $h.ForegroundColor="yellow"
                Write-Host("Getting System logs from $server")
                $h.ForegroundColor="gray"
                if(!(Test-Connection -Quiet $server -Count 5)) {
                               throw "[$server] connection not available"
                }
                try {
                               if ($server -eq $env:COMPUTERNAME) {
                                               return Get-WmiObject -Class:Win32_NTEventLogfile | where {$_.logfilename -eq "system"}
                               }

                               return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server  -Credential:$credential | where {$_.logfilename -eq "system"}
                }
                catch {
                               throw "[GetEventsLogsSystem][$server] (Ligne $($_.InvocationInfo.ScriptLineNumber)) $_"
                }
}

function GetIISlogs ([string]$server, [Management.Automation.PSCredential]$credential)
{
                $h.ForegroundColor="yellow";
                Write-Host("Getting IIS logs from $server");
                if(!(Test-Connection -Quiet $server -Count 5)) {
                               throw "[$server] connection not available";
                }
                try {
                               
                               
                               if ($server -eq $env:COMPUTERNAME) 
                                
                               {
                                    foreach($WebSite in $(get-website))

                                        {
                                            
                                            $logFilefolder="$($Website.logFile.directory)\W3SVC$($website.id)".replace("%SystemDrive%",$env:SystemDrive);
                                            $dates= $IISdate.Split(',');
                                            #testing $dates;
                                            foreach($date in $dates){
                                            
                                            $files = get-childItem -Path $logFilefolder -Recurse -Filter "*$date*.log";
                                            $files.count;
                                            if((Test-Path -Path $logFilefolder) -and ($files.count -gt 0)){
                                                #retrive the folder represented by the IIS site ID 
                                                $folder =Split-Path -Path $logFilefolder -Leaf
                                                #create the destination folder 
                                                $destf = ("{0}\{1}_{2}\{3}" -f $EventsDir, "IIS", $server, $folder)
                                                New-Item -Path $destf -Force -ItemType:directory | Out-Null;
                                                # copy all the files matching the willcard in $IISdate
                                                if($destf){
                                                    foreach($fichier in $files){
                                                    
                                                        Copy-Item $fichier.FullName -Destination $destf -Force -Container:$false;
                                                   
                                                    }
                                                }

                                                $h.ForegroundColor="green";
                                                Write-Host(" done for site " + $website.name);
                                                Write-Host("-------//-------");
                                                $h.ForegroundColor="green";
                                            }
                                            else{$h.ForegroundColor="magenta";Write-Host(" no entries for the site " + $website.name);Write-Host("-------//-------");}
                                          }  
  
                                        } 

                               }
                               else
                               {
                                    # we need to check if remote powershell is possible to the remote server
                                    Write-Host -ForegroundColor White " - Enabling WSManCredSSP for `"$server`""
                                    Enable-WSManCredSSP -Role Client -Force -DelegateComputer $server | Out-Null ;
                                    #If (!$?) {Pause "exit"; throw $_}
                                    $Session = New-PSSession -ComputerName $server
                                    # only retrive the data really need to avoid to exceed the buffer 
                                    $block = { 
                                        Import-Module 'webAdministration' -ErrorAction 0;
                                        get-website | %{($_.name + ";" + $_.id + ";" +  $_.logFile.directory)}
                                    }
                                    $rsites = Invoke-Command -Session $Session -ScriptBlock $block; 
                                    #Get-PSSession| %{ Remove-PSSession -Session $_ }
                                    foreach($WebSite in $rsites){
                                            
                                            $line = $WebSite.split(';');
                                            $logFilefolder="$($line[2])\W3SVC$($line[1])".replace("%SystemDrive%",$env:SystemDrive)
                                            $netfolder = Split-Path -Path $logFilefolder -noQualifier;
                                            $folder =Split-Path -Path $logFilefolder -Leaf;
                                            $sourcepath = ("\\" + ($server + "\C$" + $netfolder));
                                            #[bool]([System.Uri]$sourcepath).IsUnc
                                            $dates= $IISdate.Split(',');
                                            #testing $dates;
                                            foreach($date in $dates){
                                            $files = get-childItem -Path $sourcepath -Recurse -Filter "*$date*.log" ;
                                            #testing
                                            $files.count;
                                            if((Test-Path -Path $sourcepath) -and ($files.count -gt 0)){
                                                
                                                $destf = ("{0}\{1}_{2}\{3}" -f $EventsDir, "IIS", $server, $folder);
                                                #Create the destination folder with W3SVC and site ID
                                                New-Item -Path $destf -Force -ItemType:directory| Out-Null;
                                                try{
                                                     if($destf){
                                                        foreach($fichier in $files){
                                                            
                                                            Copy-Item $fichier.FullName -Destination $destf -Force -Container:$false;
                                                        }
                                                    }
                                            
                                            
                                            }
                                            catch{}
                                            Start-Sleep 2;
                                            $h.ForegroundColor="green";
                                            Write-Host( " done for site " + ($line[0]).ToString());
                                            Write-Host("------//------")
                                            $h.ForegroundColor="green";
                                            }
                                            else{$h.ForegroundColor="magenta";Write-Host(" no entries for the site " + $line[0]);Write-Host("-------//-------");}
                                          }  
                                        }                                     
                                    $h.ForegroundColor="green";
                                    Write-Host( "... end server $server");
                                    Write-Host("-------//-------") -ForegroundColor "green";
                                    $h.ForegroundColor="green";
                                    Remove-PSSession -Session $Session
                                    
                               }
                }
                catch 
                {
                               $h.ForegroundColor="red"
                               throw "$Error[0].Exception.Message"
                               Remove-PSSession -Session $Session
                }
                
}

function GetMergedUlsLOgs(){

    $h.ForegroundColor="green";
    $stime = $ULSstarttime -as [DateTime];
    $etime = $ULSendtime -as [DateTime];
    $mtime= get-date -Format d_M_HH_mm_ss
    if($stime -and $etime){
    Try{
                

            Merge-SPLogFile -Path "$EventsDir\FarmMergedLog_$mtime.log" -Overwrite -starttime ($stime).tostring() -endtime ($etime).tostring() 
                }
    catch {
                $h.ForegroundColor="red"
                throw "$Error[0].Exception.Message"
                Write-Host("check the date format ... ") 
	}
    }
    else{Write-Host("It's not possible to run the Merge-SPLogFile, please check the date format ... ")}




}

#################################################

#main
#function Get-SPFarmLogs(){}

$Error.Clear();
$h=(Get-Host).UI.RawUI
$h.ForegroundColor="DarkYellow"
write-host("There is a syntax example");
write-host('get-spfarmlogs.ps1 -user "contoso\admincc" -eventsdir C:\collectfarmlogs\logs -IISdate 150910 -ULSstarttime "06/30/20xx 18:30" -ULSendtime "06/30/20xx 19:30"');
$h.BackgroundColor="black"
$h.ForegroundColor="green"

#$password =  read-host "Provide the password for the Admin Remote Servers " -AsSecureString ;

$password= ConvertTo-SecureString “P@ssw0rd1” -AsPlainText -Force

$credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $password
$h.ForegroundColor="gray"


$srvs=$null;
if(!$servers){

    $srvtemp= Get-SPServer | ?{$_.role -ne "Invalid"} ;
    $srvs = $srvtemp.name;
    
}
else{

    $srvs = $servers.split(',');
    
}
    
foreach($server in $srvs){

        $h.ForegroundColor="red"
        $server ;
        try
            {
            
            
                if($NoEvents -eq $false){
                    # Application Event viewer
                    $events=GetEventsLogsApplication -server $server -credential $credential
                    [string]$src01 = ("\\{0}\{1}" -f $server, $events.Name) -replace ":\\", "$\"
                    $h.ForegroundColor="gray"
                    
                    $destapplication = ("{0}\{1}_{2}.evtx" -f $EventsDir, "Application", $server)
                    $newfolder = Split-Path -Path $destapplication -parent
                    #testing                    $newfolder

                    if(Test-Path -Path $newfolder){

                    Copy-Item -Path $src01 -Destination $destapplication -Force
                    Write-Host("-------//-------");
                    }
                    else{
                        
                        
                        New-Item -Path $newfolder -Force -ItemType:directory | Out-Null;

                        Copy-Item -Path $src01 -Destination $destapplication -Force
                        
                    }
            
                    # System Event viewer
                    $events = GetEventsLogsSystem -server $server -credential $credential
                    $h.ForegroundColor="yellow"
                    [string]$src02 = ("\\{0}\{1}" -f $server, $events.Name) -replace ":\\", "$\"
                    
                    $destsystem= ("{0}\{1}_{2}.evtx" -f $EventsDir, "System",$server);

                    Copy-Item -Path $src02 -Destination $destsystem -Force

                    Write-Host("-------//-------");
                    

                    
                }
            
               # IIS logs
                if($IISdate){
                        
                        GetIISlogs -server $server -credential $credential ;
                    
                }
                else{Write-Host("-------//-------");}
            
          }
          catch{throw "$Error[0].Exception.Message"}
	  

}
	
  
if($ULSstarttime -and $ULSendtime){

        GetMergedUlsLOgs;
        
 }

	
$h.BackgroundColor="black";
$h.ForegroundColor="white";   

Write-Host "command ended...";

         



     
