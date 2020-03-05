#!/bin/bash
##set -x

PATH="/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin"
TERM="vt100"
export TERM PATH

SUCCESS=0
ERROR=1

let exit_code=${SUCCESS}

# This function shows what has been entered so far at each stage
function supplied_data() {
    let return_code=${SUCCESS}

    echo "==============" >&2
    echo "Supplied Data:" >&2
    echo "  GCP Project: ${my_gcp_project}" >&2
    echo "  GCP Instance Zone: ${my_instance_zone}" >&2
    echo "  GCP Instance Region: ${my_instance_region}" >&2
    echo "  CloudSQL Instance Name: ${my_instance_name}" >&2
    echo "  CloudSQL SRN: ${my_instance_srn}" >&2
    echo "  CloudSQL MySQL Version: ${my_mysql_version}" >&2
    echo "  Source Host IP Address: ${my_source_host_ip}" >&2
    echo "  Source Host Port: ${my_source_host_port}" >&2
    echo "  Source Host Username: ${my_source_username}" >&2
    echo "  MySQL Dump Storage Bucket: gs://${my_storage_bucket}" >&2
    echo "  MySQL Dump Filename: ${my_dumpfile_name}" >&2
    echo "  CloudSQL Machine Type: ${my_machine_type}" >&2
    echo "  CloudSQL Storage Size: ${my_storage_size}" >&2
    echo "==============" >&2
    echo >&2
    echo >&2
    echo "--------------" >&2

    return ${return_code}
}

# This function provides the stage choreography
function main() {
    let return_code=${SUCCESS}
    
    clear
    my_gcp_project=$(valid_gcp_project)                                                         &&
    my_project_initials=$(echo "${my_gcp_project}" | sed -e 's|-| |g' -e 's/\(.\)[^ ]* */\1/g') &&

    clear
    my_instance_zone=$(valid_gcp_zone ${my_gcp_project})             &&
    my_instance_region=$(echo "${my_instance_zone}" | sed 's/..$//') &&

    clear
    my_instance_name=$(valid_sql_name "${my_gcp_project}")                &&
    my_instance_srn=$(echo "${my_instance_name}" | sed -e 's|\(-gdbm-\)|-srn\1|g') &&

    clear
    my_mysql_version=$(valid_mysql_version) &&

    clear
    my_source_host_ip=$(valid_source_host_ip) &&

    clear
    my_source_host_port=$(valid_source_host_port)                                                             &&
    echo "helo" | socat - TCP4:${my_source_host_ip}:${my_source_host_port},connect-timeout=2 > /dev/null 2>&1 &&

    clear
    my_source_username=$(remote_db_credentials) &&

    clear
    my_storage_bucket=$(valid_gcs_bucket) &&

    clear
    my_dumpfile_name="${my_instance_name}.$(date +%Y%m%d).sql"

    clear
    my_machine_type=$(valid_instance_tier) &&

    clear
    my_storage_size=$(valid_disk_size) &&

    clear
    echo_commands
    return ${?}
}

# This function checks that the GCP project provided is valid
function valid_gcp_project() {
    let return_code=${SUCCESS}

    local this_gcp_project=""

    while [ -z "${this_gcp_project}" ]; do
        supplied_data
        read -p "GCP Project name: " this_gcp_project

        # Make sure our gcloud project exists
        let gcp_project_exists=$(gcloud projects list | egrep -iv "^PROJECT_ID" | awk '{print $1}' | egrep -c "^${this_gcp_project}$")

        if [ ${gcp_project_exists} -eq 0 ]; then
            echo "Gcloud project '${this_gcp_project}' does not exist" >&2
            this_gcp_project=""
            sleep 3
        fi

    done

    echo "${this_gcp_project}"
    return ${return_code}
}

# This function generates a list of valid zones for the given GCP project
function valid_gcp_zone() {
    let return_code=${SUCCESS}

    local this_project="${1}"

    if [ ! -z "${this_project}" ]; then
        local zone_list=$(gcloud --project="${this_project}" compute zones list | egrep -v "^NAME" | awk '{print $1}')
        local zone_array=(${zone_list})
        local max_element=""
        let max_element=${#zone_array[@]}-1

        local max_string_length=""
        let max_string_length=0

        # Figure out the longest element string length ... we'll use it for output padding later
        for element in ${zone_array[@]} ; do
            let this_element_string_length=$(echo "${element}" | wc -c)

            if [ ${this_element_string_length} -gt ${max_string_length} ]; then
                let max_string_length=${this_element_string_length}
            fi

        done

        # Build a list of choices
        local this_zone=""

        while [ -z "${this_zone}" ]; do
            supplied_data
            echo "Valid GCP zones are as follows: " >&2
            echo >&2

            local element_counter=""
            local next_element_counter=""

            let element_counter=0
            let next_element_counter=0
            
            while [ ${element_counter} -le ${max_element} ] ; do
                local this_element="${zone_array[$element_counter]}"
                local this_element_length=""
                let this_element_length=$(echo "${this_element}" | wc -c)

                local element_padding_delta=""
                let element_padding_delta=${max_string_length}-${this_element_length}

                local element_padding=""

                while [ ${element_padding_delta} -gt 0 ]; do
                    element_padding+=" "
                    let element_padding_delta-=1
                done

                let next_element_counter=${element_counter}+1
                local next_element="${zone_array[$next_element_counter]}"
                local index_padding=""

                if [ ${next_element_counter} -lt 10 ]; then
                    index_padding=" "
                fi

                if [ ! -z "${next_element}" ]; then
                    echo -e "  [${element_counter}]${index_padding} ${this_element}${element_padding}\t[${next_element_counter}]${index_padding} ${next_element}" >&2
                    let element_counter+=1
                else
                    echo "  [${element_counter}]${index_padding} ${this_element}" >&2
                fi

                let element_counter+=1
            done

            echo >&2
            read -p "Enter the number corresponding with the zone of choice: " array_index

            array_index=$(echo "${array_index}" | egrep -v "[^0-9]")
            
            if [ -z "${array_index}" ]; then
                let array_index=${max_element}+1
            fi

            if [ ${array_index} -lt 0 -o ${array_index} -gt ${max_element} ]; then
                echo "Invalid choice" >&2
                sleep 3
            else
                this_zone="${zone_array[$array_index]}"
            fi

        done 

        echo "${this_zone}"
    else
        let return_code=${ERROR}
    fi

    return ${return_code}
}

# This function makes sure that the CloudSQL SRN/Instance name provided is 
# unique and matches a modicum of VST naming requirements
function valid_sql_name() {
    let return_code=${SUCCESS}

    local this_project="${1}"

    if [ ! -z "${this_project}" -a ! -z "${my_project_initials}" ]; then
        local this_instance_name=""

        local has_gdbm=""
        local has_project_initials=""

        let has_gdbm=0
        let has_project_initials=0

        while [ -z "${this_instance_name}" ]; do
            supplied_data

            local is_unique=""
            let is_unique=0

            read -p "Enter Cloud SQL instance Name: " this_instance_name 

            # A valid CloudSQL instance name has the regex '-gdbm-' in it 
            # and begins with the project initials
            let has_gdbm=$(echo "${this_instance_name}" | egrep -c '\-gdbm\-')
            let has_project_initials=$(echo "${this_instance_name}" | egrep -c "^${my_project_initials}\-")

            if [ ${has_gdbm} -gt 0 -a ${has_project_initials} -gt 0 ]; then
                # Make sure our instance name is unique
                let is_unique=$(gcloud --project=${this_project} sql instances list 2> /dev/null | egrep -v "^NAME" 2> /dev/null | awk '{print $1}' 2> /dev/null | egrep -c "^${this_instance_name}$")

                if [ ${is_unique} -gt 0 ]; then
                    echo "CloudSQL instance name '${this_instance_name}' is not unique within GCP project '${this_project}'" >&2
                    this_instance_name=""
                    sleep 3
                fi

            else
                echo "Malformed instance name '${this_instance_name}' - must start with the project initials '${my_project_initials}' and contain the pattern '-gdbm-'" >&2
                this_instance_name=""
                sleep 3
            fi

        done

        echo "${this_instance_name}"
    else
        let return_code=${ERROR}
    fi

    return ${return_code}
}

# This function provides a list of valid MySQL versions from which to choose for CloudSQL 
function valid_mysql_version() {
    let return_code=${SUCCESS}

    local valid_mysql_versions="MYSQL_5_6 MYSQL_5_7"
    local mysql_version_array=(${valid_mysql_versions})
    local max_element=""
    let max_element=${#mysql_version_array[@]}-1

    local this_mysql_version=""

    while [ -z "${this_mysql_version}" ]; do
        supplied_data
        echo "Valid versions of MySQL are as follows:" >&2
        echo >&2

        local element_counter=""
        let element_counter=0

        for element in ${mysql_version_array[@]} ; do
            version_number=$(echo "${element}" | sed -e 's|^.*\([0-9]\)_\(0-9\)$|\1\.\2|g')
            echo "  [${element_counter}] MySQL ${version_number}" >&2
            let element_counter+=1
        done

        echo >&2
        read -p "Enter the number corresponding to the MySQL version of choice: " array_index

        array_index=$(echo "${array_index}" | egrep -v "[^0-9]")
            
        if [ -z "${array_index}" ]; then
            let array_index=${max_element}+1
        fi

        if [ ${array_index} -lt 0 -o ${array_index} -gt ${max_element} ]; then
            echo "Invalid choice" >&2
            sleep 3
        else
            this_mysql_version="${mysql_version_array[$array_index]}"
        fi

    done 

    echo "${this_mysql_version}"
    return ${return_code}
}

function valid_source_host_ip() {
    let return_code=${SUCCESS}

    local this_source_host_ip=""

    while [ -z "${this_source_host_ip}" ]; do
        supplied_data
        read -p "Enter the IP Address of the Source Host: " this_source_host_ip

        local is_valid_address=""

        # Gotta know our platform
        local this_plaform="uname -s | tr '[A-Z]' '[a-z]'"

        case "${this_platform}" in

            darwin)
                let is_valid_address=$(ipcalc ${this_source_host_ip} 2> /dev/null | egrep -ic "^invalid address:")
            ;;

            linux)
                ipcalc -c ${this_source_host_ip} > /dev/null 2>&1
                let is_valid_address=${?}
            ;;

        esac

        if [ ${is_valid_address} -ne 0 ]; then
            echo "Entered value '${this_source_host_ip}' is not a valid IP address" >&2
            this_source_host_ip=""
        fi

    done

    echo "${this_source_host_ip}"
    return ${return_code}
}

function valid_source_host_port() {
    let return_code=${SUCCESS}

    local this_source_host_port=""

    while [ -z "${this_source_host_port}" ]; do
        supplied_data
        read -p "Enter the Port of the Source Host '${my_source_host_ip}': " this_source_host_port

        local port_lower_bound=""
        local port_upper_bound=""

        local is_valid_porti1=""
        local is_valid_porti2=""

        let port_lower_bound=1024
        let port_upper_bound=65535

        let is_valid_port1=$(echo "${port_lower_bound} < ${this_source_host_port}" | bc)
        let is_valid_port2=$(echo "${this_source_host_port} < ${port_upper_bound}" | bc)

        if [ ${is_valid_port1} -eq 1 -a ${is_valid_port2} -eq 1 ]; then
            true
        else
            echo "Entered value '${this_source_host_port}' is not a valid port " >&2
            this_source_host_port=""
        fi

    done

    echo "${this_source_host_port}"
    return ${return_code}
}

function remote_db_credentials() {
    let return_code=${SUCCESS}

    local remote_db_username=""

    while [ -z "${remote_db_username}" ]; do
        supplied_data
        read -p "Enter the Remote Database Username for source host '${my_source_host_ip}:${my_source_host_port}': " remote_db_username
    done

    echo "${remote_db_username}"
    return ${return_code}
}

function valid_gcs_bucket() {
    let return_code=${SUCCESS}

    local this_gcs_bucket=""

    while [ -z "${this_gcs_bucket}" ]; do
        supplied_data
        read -p "Enter a valid GCS bucket name: " this_gcs_bucket

        this_gcs_bucket=$(echo "${this_gcs_bucket}" | sed -e 's|^gs://||g')
        gsutil ls gs://${this_gcs_bucket} > /dev/null 2>&1

        if [ ${?} -ne ${SUCCESS} ]; then
            echo "Unable to access GCS bucket 'gs://${this_gcs_bucket}'" >&2
            this_gcs_bucket=""
        fi

    done

    echo "${this_gcs_bucket}"
    return ${return_code}
}

function valid_instance_tier() {
    let return_code=${SUCCESS}

    local this_machine_type=""
    local array_index=""

    local tier_header="TIER\t\t\t\tRAM\t\tDISK"
    local regional_tiers_list=$(gcloud --project=${my_gcp_project} sql tiers list | egrep "\b${my_instance_region}\b" | awk '{print $1 "--RAM:" $(NF-3) "-" $(NF-2) "--DISK:" $(NF-1) "-" $NF}')
    local regional_tiers_array=(${regional_tiers_list})
    local max_element=""
    let max_element=${#regional_tiers_array[@]}-1

    local max_string_length=""
    let max_string_length=0

    # Figure out the longest machine type string
    for i in ${regional_tiers_array[@]} ; do
        let machine_type_string_length=$(echo "${i}" | awk -F'--' '{print $1}' | wc -c)

        if [ ${machine_type_string_length} -gt ${max_string_length} ]; then
            let max_string_length=${machine_type_string_length}
        fi
   
    done

    while [ -z "${this_machine_type}" ]; do
        supplied_data
        local element_counter=""
        let element_counter=0

        for element in ${regional_tiers_array[@]} ; do
            local element_padding=""
            local element_padding_delta=""
            let element_padding_delta=0
            local index_padding=""

            if [ ${element_counter} -lt 10 ]; then
                index_padding=" "
            fi

            machine_type=$(echo "${element}" | awk -F'--' '{print $1}')
            ram_info=$(echo "${element}" | awk -F'--' '{print $2}')
            disk_info=$(echo "${element}" | awk -F'--' '{print $NF}')

            machine_type_string_length=$(echo "${machine_type}" | wc -c)
            let element_padding_delta=${max_string_length}-${machine_type_string_length}

            while [ ${element_padding_delta} -gt 0 ]; do
                element_padding+=" "
                let element_padding_delta-=1
            done

            ram_size=$(echo "${ram_info}" | awk -F':' '{print $NF}' | awk -F'-' '{print $1}')
            ram_size_units=$(echo "${ram_info}" | awk -F':' '{print $NF}' | awk -F'-' '{print $NF}')

            disk_size=$(echo "${disk_info}" | awk -F':' '{print $NF}' | awk -F'-' '{print $1}')
            disk_size_units=$(echo "${disk_info}" | awk -F':' '{print $NF}' | awk -F'-' '{print $NF}')

            if [ ${element_counter} -eq 0 ]; then
                echo "Valid Machine Tiers in region '${my_instance_region}':" >&2
                echo "============================================================" >&2
                echo -e "${tier_header}"                                            >&2
                echo "------------------------------------------------------------" >&2
            fi

            echo -e "[${element_counter}]${index_padding} ${machine_type}${element_padding}\t\t${ram_size} ${ram_size_units}\t\t${disk_size} ${disk_size_units}" >&2
            let element_counter+=1
        done

        echo >&2
        read -p "Enter the number corresponding with the machine tier of choice: " array_index

        array_index=$(echo "${array_index}" | egrep -v "[^0-9]")
        
        if [ -z "${array_index}" ]; then
            let array_index=${max_element}+1
        fi

        if [ ${array_index} -lt 0 -o ${array_index} -gt ${max_element} ]; then
            echo "Invalid choice" >&2
            sleep 3
        else
            this_machine_type=$(echo "${regional_tiers_array[$array_index]}" | awk -F'--' '{print $1}')
        fi

    done

    echo "${this_machine_type}"
    return ${return_code}
}

function valid_disk_size() {
    let return_code=${SUCCESS}

    local this_disk_size=""
    local storage_lower_limit=""
    local storage_upper_limit=""

    let storage_lower_limit=10
    let storage_upper_limit=30720

    while [ -z "${this_disk_size}" ]; do
        supplied_data
        read -p "Enter the desired disk storage size in GB [${storage_lower_limit}-${storage_upper_limit}]: " this_input

        this_input=$(echo "${this_input}" | egrep -v "[^0-9]")
        
        if [ -z "${this_input}" ]; then
            let this_input=0
        fi

        if [ ${this_input} -lt ${storage_lower_limit} -o ${this_input} -gt ${storage_upper_limit} ]; then
            echo "Invalid choice" >&2
            sleep 3
        else
            this_disk_size="${this_input}"
        fi

    done

    echo "${this_disk_size}"
    return ${return_code}
}

function echo_commands() {
    let return_code=${SUCCESS}

    supplied_data
    # If we get here, we think we have enough viable information to do a thing

    # This creates the answer file
    echo "gcloud beta sql instances create ${my_instance_srn} \\"
    echo "    --project=${my_gcp_project} \\"
    echo "    --region=${my_instance_region} \\"
    echo "    --database-version=${my_mysql_version} \\"
    echo "    --source-ip-address=${my_source_host_ip} \\"
    echo "    --source-port=${my_source_host_port}"
    
    # This creates the instance that wiil use the answer file to setup a replica
    echo "gcloud beta sql instances create ${my_instance_name} \\"
    echo "    --project=${my_gcp_project} \\"
    echo "    --zone-${my_instance_zone} \\"
    echo "    --master-instance-name=${my_instance_srn} \\"
    echo "    --master-username=${my_source_username} \\"
    echo "    --prompt-for-master-password \\"
    echo "    --master-dump-file-path=gs://${my_storage_bucket}/${my_dumpfile_name} \\"
    echo "    #--master-ca-certificate-path=[SOURCE_SERVER_CA_PATH] \\"
    echo "    #--client-certificate-path=[CLIENT_CERT_PATH] \\"
    echo "    #--client-key-path=[PRIVATE_KEY_PATH] \\"
    echo "    --tier=${my_machine_type} \\"
    echo "    --storage-size=${my_storage_size}"

    return ${return_code}
}

main
let exit_code=${?}

exit ${exit_code}

