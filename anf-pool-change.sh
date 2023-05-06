#!/bin/bash
set -euo pipefail

# Mandatory variables for ANF resources
# Change variables according to your environment 
SUBSCRIPTION_ID="<Subscription ID>"
LOCATION="WestUS"
RESOURCEGROUP_NAME="My-rg"
VNET_NAME="sourcevnet"
SUBNET_NAME="sourcesubnet"
NETAPP_ACCOUNT_NAME="netapptestaccount"
SOURCE_NETAPP_POOL_NAME="pool1"
SOURCE_SERVICE_LEVEL="Premium"
DESTINATION_NETAPP_POOL_NAME="pool2"
DESTINATION_SERVICE_LEVEL="Standard"
NETAPP_POOL_SIZE_TIB=4
NETAPP_VOLUME_NAME="netappvolume"
NETAPP_VOLUME_SIZE_GIB=100
PROTOCOL_TYPE="NFSv4.1"
SHOULD_CLEANUP="false"

# Exit error code
ERR_ACCOUNT_NOT_FOUND=100

# Utils Functions
display_bash_header()
{
    echo "-----------------------------------------------------------------------------------------------------------------------------------------"
    echo "Azure NetApp Files CLI NFS Sample  - Sample Bash script that perform Capacity pool change on Azure NetApp Files Volume - NFSv4.1 protocol"
    echo "-----------------------------------------------------------------------------------------------------------------------------------------"
}

display_cleanup_header()
{
    echo "----------------------------------------"
    echo "Cleaning up Azure NetApp Files Resources"
    echo "----------------------------------------"
}

display_message()
{
    time=$(date +"%T")
    message="$time : $1"
    echo $message
}

#----------------------
# ANF CRUD functions
#----------------------

# Create Azure NetApp Files Account
create_or_update_netapp_account()
{    
    local __resultvar=$1
    local _NEW_ACCOUNT_ID=""

    _NEW_ACCOUNT_ID=$(az netappfiles account create --resource-group $RESOURCEGROUP_NAME \
        --name $NETAPP_ACCOUNT_NAME \
        --location $LOCATION | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_ACCOUNT_ID}'"
    else
        echo "${_NEW_ACCOUNT_ID}"
    fi
}

# Create Azure NetApp Files Capacity Pool
create_or_update_netapp_pool()
{    
    local _POOL_NAME=$1
    local _SERVICE_LEVEL=$2
    local __resultvar=$3
    local _NEW_POOL_ID=""

    _NEW_POOL_ID=$(az netappfiles pool create --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --name $_POOL_NAME \
        --location $LOCATION \
        --size $NETAPP_POOL_SIZE_TIB \
        --service-level $_SERVICE_LEVEL | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_POOL_ID}'"
    else
        echo "${_NEW_POOL_ID}"
    fi
}

# Create Azure NetApp Files Volume
create_or_update_netapp_volume()
{
    local __resultvar=$1
    local _NEW_VOLUME_ID=""

    _NEW_VOLUME_ID=$(az netappfiles volume create --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --file-path $NETAPP_VOLUME_NAME \
        --pool-name $SOURCE_NETAPP_POOL_NAME \
        --name $NETAPP_VOLUME_NAME \
        --location $LOCATION \
        --service-level $SOURCE_SERVICE_LEVEL \
        --usage-threshold $NETAPP_VOLUME_SIZE_GIB \
        --vnet $VNET_NAME \
        --subnet $SUBNET_NAME \
        --protocol-types $PROTOCOL_TYPE | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_VOLUME_ID}'"
    else
        echo "${_NEW_VOLUME_ID}"
    fi
}

# Change pool for Azure NetApp Files Volume
update_netapp_volume_pool()
{    
    local _NEW_POOL_ID=$1    
    
    az netappfiles volume pool-change --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --pool-name $SOURCE_NETAPP_POOL_NAME \
        --name $NETAPP_VOLUME_NAME \
        --new-pool-resource-id $_NEW_POOL_ID
}

# Get NetApp Files Volume ID
get_netapp_volume_id()
{
    local _RESOURCEGROUP_NAME=$1
    local _NETAPP_ACCOUNT_NAME=$2
    local _NETAPP_POOL_NAME=$3
    local _NETAPP_VOLUME_NAME=$4    
    local __resultvar=$5
    local _NEW_VOLUME_ID=""

    _NEW_VOLUME_ID=$(az netappfiles volume show --resource-group $_RESOURCEGROUP_NAME \
        --account-name $_NETAPP_ACCOUNT_NAME \
        --pool-name $_NETAPP_POOL_NAME \
        --name $_NETAPP_VOLUME_NAME | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_VOLUME_ID}'"
    else
        echo "${_NEW_VOLUME_ID}"
    fi
}


#---------------------------
# ANF cleanup functions
#---------------------------

# Delete Azure NetApp Files Account
delete_netapp_account()
{
    az netappfiles account delete --resource-group $RESOURCEGROUP_NAME \
        --name $NETAPP_ACCOUNT_NAME    
}

# Delete both Primary and Secondary Azure NetApp Files Capacity Pool
delete_netapp_pool()
{
    local _RESOURCEGROUP_NAME=$1
    local _NETAPP_ACCOUNT_NAME=$2
    local _NETAPP_POOL_NAME=$3

    az netappfiles pool delete --resource-group $_RESOURCEGROUP_NAME \
        --account-name $_NETAPP_ACCOUNT_NAME \
        --name $_NETAPP_POOL_NAME     
}

# Delete Azure NetApp Files Volume
delete_netapp_volume()
{
    az netappfiles volume delete --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --pool-name $DESTINATION_NETAPP_POOL_NAME \
        --name $NETAPP_VOLUME_NAME
}

# Return resource type from resource ID
get_resource_type()
{
    local _RESOURCE_ID=$1
    local __resultvar=$2    
    
    _RESOURCE_ID="${_RESOURCE_ID//\// }"   
    OIFS=$IFS; IFS=' '; read -ra ANF_RESOURCES_ARRAY <<< $_RESOURCE_ID; IFS=$OIFS
    
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${ANF_RESOURCES_ARRAY[-2]}'"
    else
        echo "${ANF_RESOURCES_ARRAY[-2]}"
    fi
}

#----------------------------
# Waiting resources functions
#----------------------------

# Wait for resources to succeed 
wait_for_resource()
{
    local _RESOURCE_ID=$1

    local _RESOURCE_TYPE="";get_resource_type $_RESOURCE_ID _RESOURCE_TYPE

    for i in {1..60}; do
        sleep 10
        if [[ "${_RESOURCE_TYPE,,}" == "netappaccounts" ]]; then
            _ACCOUNT_STATUS=$(az netappfiles account show --ids $_RESOURCE_ID | jq -r ".provisioningState")
            if [[ "${_ACCOUNT_STATUS,,}" == "succeeded" ]]; then
                break
            fi        
        elif [[ "${_RESOURCE_TYPE,,}" == "capacitypools" ]]; then
            _POOL_STATUS=$(az netappfiles pool show --ids $_RESOURCE_ID | jq -r ".provisioningState")
            if [[ "${_POOL_STATUS,,}" == "succeeded" ]]; then
                break
            fi                    
        elif [[ "${_RESOURCE_TYPE,,}" == "volumes" ]]; then
            _VOLUME_STATUS=$(az netappfiles volume show --ids $_RESOURCE_ID | jq -r ".provisioningState")
            if [[ "${_VOLUME_STATUS,,}" == "succeeded" ]]; then
                break
            fi
        else
            _SNAPSHOT_STATUS=$(az netappfiles snapshot show --ids $_RESOURCE_ID | jq -r ".provisioningState")
            if [[ "${_SNAPSHOT_STATUS,,}" == "succeeded" ]]; then
                break
            fi           
        fi        
    done   
}

# Wait for resources to get fully deleted
wait_for_no_resource()
{
    local _RESOURCE_ID=$1

    local _RESOURCE_TYPE="";get_resource_type $_RESOURCE_ID _RESOURCE_TYPE
 
    for i in {1..60}; do
        sleep 10
        if [[ "${_RESOURCE_TYPE,,}" == "netappaccounts" ]]; then
            az netappfiles account show --ids $_RESOURCE_ID || break                    
        elif [[ "${_RESOURCE_TYPE,,}" == "capacitypools" ]]; then
            az netappfiles pool show --ids $_RESOURCE_ID || break                           
        elif [[ "${_RESOURCE_TYPE,,}" == "volumes" ]]; then
            az netappfiles volume show --ids $_RESOURCE_ID || break
        else
            az netappfiles snapshot show --ids $_RESOURCE_ID || break         
        fi        
    done   
}

# Script Start
# Display Header
display_bash_header

# Login and Authenticate to Azure
display_message "Authenticating into Azure"
az login

# Set the target subscription 
display_message "setting up the target subscription"
az account set --subscription $SUBSCRIPTION_ID

display_message "Creating Azure NetApp Files Account ..."
{    
    NEW_ACCOUNT_ID="";create_or_update_netapp_account NEW_ACCOUNT_ID
    wait_for_resource $NEW_ACCOUNT_ID
    display_message "Azure NetApp Files Account was created successfully: $NEW_ACCOUNT_ID"
} || {
    display_message "Failed to create Azure NetApp Files Account"
    exit 1
}

display_message "Creating Azure NetApp Files Source capacity Pool ..."
{
    NEW_PRIMARY_POOL_ID="";create_or_update_netapp_pool $SOURCE_NETAPP_POOL_NAME $SOURCE_SERVICE_LEVEL NEW_PRIMARY_POOL_ID
    wait_for_resource $NEW_PRIMARY_POOL_ID
    display_message "Azure NetApp Files source pool was created successfully: $NEW_PRIMARY_POOL_ID"
} || {
    display_message "Failed to create Azure NetApp Files source pool"
    exit 1
}

NEW_SECONDARY_POOL_ID=""
display_message "Creating Azure NetApp Files destination capacity Pool ..."
{
    create_or_update_netapp_pool $DESTINATION_NETAPP_POOL_NAME $DESTINATION_SERVICE_LEVEL NEW_SECONDARY_POOL_ID
    wait_for_resource $NEW_SECONDARY_POOL_ID
    display_message "Azure NetApp Files destination pool was created successfully: $NEW_SECONDARY_POOL_ID"
} || {
    display_message "Failed to create Azure NetApp Files destination pool"
    exit 1
}

display_message "Creating Azure NetApp Files Volume..."
{
    NEW_VOLUME_ID="";create_or_update_netapp_volume NEW_VOLUME_ID
    wait_for_resource $NEW_VOLUME_ID
    display_message "Azure NetApp Files volume was created successfully: $NEW_VOLUME_ID"
} || {
    display_message "Failed to create Azure NetApp Files volume"
    exit 1
}

display_message "Performing pool change for Volume: $NETAPP_VOLUME_NAME ..."
{
    update_netapp_volume_pool $NEW_SECONDARY_POOL_ID
    display_message "Azure NetApp Files volume was moved successfully to : $DESTINATION_NETAPP_POOL_NAME"
} || {
    display_message "Failed to perform pool change for targeted Azure NetApp Files volume"
    exit 1
}

# Get new volume ID after moving to the new Pool
display_message "Retrieving the new Volume ID"
{
    POST_MOVE_VOLUME_ID="";get_netapp_volume_id $RESOURCEGROUP_NAME $NETAPP_ACCOUNT_NAME $DESTINATION_NETAPP_POOL_NAME $NETAPP_VOLUME_NAME POST_MOVE_VOLUME_ID
    wait_for_resource $POST_MOVE_VOLUME_ID
    display_message "NEW Azure NetApp Files Volume is: $POST_MOVE_VOLUME_ID"
} || {
    display_message "Failed to retrieve Azure NetApp Files volume ID"
    exit 1
}

# Clean up resources
if [[ "$SHOULD_CLEANUP" == true ]]; then
    # Display cleanup header
    display_cleanup_header

    # Delete Volume
    display_message "Deleting Azure NetApp Files Volume..."
    {
        delete_netapp_volume
        wait_for_no_resource $POST_MOVE_VOLUME_ID
        display_message "Azure NetApp Files volume was deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files volume"
        exit 1
    }

    # Delete source Capacity Pool
    display_message "Deleting source Azure NetApp Files Pool ..."
    {
        delete_netapp_pool $RESOURCEGROUP_NAME $NETAPP_ACCOUNT_NAME $SOURCE_NETAPP_POOL_NAME
        wait_for_no_resource $NEW_PRIMARY_POOL_ID      
        display_message "Azure NetApp Files pools were deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files pools"
        exit 1
    }

    # Delete destination Capacity Pool
    display_message "Deleting destination Azure NetApp Files Pool ..."
    {
        delete_netapp_pool $RESOURCEGROUP_NAME $NETAPP_ACCOUNT_NAME $DESTINATION_NETAPP_POOL_NAME        
        wait_for_no_resource $NEW_SECONDARY_POOL_ID
        display_message "Azure NetApp Files pools were deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files pools"
        exit 1
    }

    # Delete Account
    display_message "Deleting Azure NetApp Files Account ..."
    {
        delete_netapp_account
        display_message "Azure NetApp Files Account was deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files Account"
        exit 1
    }
fi
