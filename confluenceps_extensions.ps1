function Get-ConfluenceGroups
{
    (Invoke-ConfluenceMethod -uri ($PSDefaultParameterValues."Get-ConfluencePage:ApiUri" + "/group") | %{$_.name})
}
function Get-ConfluenceGroupMembers
{
    [CmdletBinding()]
    param()
        DynamicParam {
     
            # Set the dynamic parameters' name
            $ParameterName = 'GroupName'
    
            # Create the dictionary
            $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    
            # Create the collection of attributes
            $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    
            # Create and set the parameters' attributes
            $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
            $ParameterAttribute.Mandatory = $true
            $ParameterAttribute.Position = 1
    
            # Add the attributes to the attributes collection
            $AttributeCollection.Add($ParameterAttribute)
    
            # Generate and set the ValidateSet
            $arrSet = (Invoke-ConfluenceMethod -uri ($PSDefaultParameterValues."Get-ConfluencePage:ApiUri" + "/group") | %{$_.name})
            $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)
    
            # Add the ValidateSet to the attributes collection
            $AttributeCollection.Add($ValidateSetAttribute)
    
            # Create and return the dynamic parameter
            $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [array], $AttributeCollection)
            $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
            return $RuntimeParameterDictionary
        }
    
    begin {
        $GroupName = $PSBoundParameters[$ParameterName]
            trap {
                $Error[0].Exception
                $Error[0].InvocationInfo
                break
            }
        $BaseURI = $PSDefaultParameterValues."Get-ConfluencePage:ApiUri"
    }

    process {
        try {
            $GroupObject = Invoke-ConfluenceMethod -uri ("$BaseURI" + "/group") | ?{$_.name -eq $GroupName}
            $GroupMembers = Invoke-ConfluenceMethod -uri ($GroupObject._links.self + "/member")
        }
        
        catch {
            throw "Failure obtaining group details"
        }
    }

    end {
        return $GroupMembers
    }
}

Function Remove-InvalidFileNameChars {
    param(
      [Parameter(Mandatory=$true,
        Position=0,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
      [String]$Name
    )
  
    $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
    $re = "[{0}]" -f [RegEx]::Escape($invalidChars)
    return ($Name -replace $re)
  }

function Copy-ConfluenceTree {
    [CmdletBinding()]
    param($HighestNodeID)
    $global:CopyConfluenceRoot = $pwd
    try
    {
        $TopPage = Get-ConfluencePage -ID $HighestNodeID
    }
    catch
    {
        write-error "Couldn't get confluence page based on ID. Check your login parameters or other things and try again."
    }
    if ($TopPage)
    {
        mkdir $TopPage.ID
        $topPagePath = ($pwd.path + "\" + $topPage.ID + "\")
        $topPage | Export-CliXml (Join-Path -Path $topPagePath -ChildPath ((Remove-InvalidFileNameChars $topPage.title) + ".xml"))
        cd $topPagePath
        foreach ($attachment in (Get-ConfluenceAttachment $topPage.ID)) {
            Write-Verbose ("Downloading Attachment: " + $attachment.Title)
            Get-ConfluenceAttachmentFile $attachment
        }
        cd ..
    }
    else
    {
        write-error "Requested Confluence page root not found."
        return
    }
    #Private recursion function to build confluence tree.
    #Confluence API doesn't support returning nested child page objects
    function priv_GetNodes {
        [CmdletBinding()]
        param ($CallingNode)
        #Recursion parameter for this function is the parent calling node, which is a file path on the file system
        #the design of this tool depends on keeping "extra" short directory names due to windows 255 character limitation
        #on total path
        #
        #the primary key for indexing the tree is the confluence page ID which is presumably unique across the entire
        #server that it is polling. 
        #the intent of this service is to generate a tree object, and create several token files in each directory for
        #post processing of the directory structure locally since the rest API is painfully slow.
        #
        #region get current directory object and directory items
        $children = gci -directory $pwd | %{$_.Name}
        if ($children) {
            #if children found on this iteration of the callstack, process for more objects.
            write-verbose "Children found, processing current level."
            foreach ($child in $children) {
                #descend into the very next child entry. When completed processing this iteration is collapsed again.
                write-verbose "Descending one level to $child"
                cd $child
                #directory structure is used as marker position

                #makes call with confluencePS stack. 
                $childPages = Get-ConfluenceChildPage -PageID $child
                foreach ($page in $childPages) {
                    #create a directory with the confluence Page ID as the name. this is for simplifying the processing of the
                    #tree objects. I could probably do this in a giant .net object or a big xml file too. But here I am,
                    #treating the file system as a database.
                    mkdir $page.ID
                    #generate an empty "markdown" file with the full name of the confluence page. perhaps in future
                    #iterations I suppose this could also rename/prune these files if people move directories around.
                    $pagePath = ($pwd.path + "\" + $page.ID + "\")
                    $pageFileName = ($pwd.path + "\" + $page.ID + "\" + ((Remove-InvalidFileNameChars $page.title) + ".xml"))
                    $page | Export-CliXml (Join-Path -Path $pagePath -ChildPath ((Remove-InvalidFileNameChars $page.title) + ".xml"))
                    cd $pagePath
                    foreach ($attachment in (Get-ConfluenceAttachment $page.ID)) {
                        Write-Verbose ("Downloading Attachment: " + $attachment.Title)
                        Get-ConfluenceAttachmentFile $attachment 2>&1
                    }
                    cd ..

                    #also generate a file with the confluence page ID as the name. This is used in post-processing as a marker
                    #for during the friendly-rename operation
                    #$page.URL > ($pwd.path + "\" + $page.ID + "\" + (($page.ID.ToString()) + ".ConfID"))
                }
                
                #recurse itself to call the next path since we found children. During the next recursion depth, if we poll for
                #pages in confluence and none are found, this portion of the IF logic will test false and execute the ELSE
                #statement below, which simply returns us back to the calling "node" aka directory that was previously called
                #I am interested to see how much memory this might consume! (probably a lot)
                priv_GetNodes -CallingNode $pwd.path
                write-verbose ("Ascending to Calling Node " + (get-item $CallingNode).Name)
                #exit the node when complete (if the recursion tests false for more items to add) 
                #so we're at the right callstack level
                if ($CallingNode -eq $null) {
                    cd $CopyConfluenceRoot
                }
                else {
                    cd $CallingNode
                }
            }
        }
        else
        {
            write-verbose ("Node has no more children. Returning to " + (get-item $pwd).Parent.Name)
            cd $CallingNode
            #IF was false, no further nods found so return back to previous callstack
            return
        }
    }
    priv_GetNodes
}