#!/bin/bash -xe

cd /root

region="${region}"
cluster_secrets_arn="${cluster_secrets_arn}"
cluster_sg_id="${cluster_sg_id}"
cluster_name="${cluster_name}"
cluster_persistent_bucket_uris="${cluster_persistent_bucket_uris}"
cluster_persistent_storage_type="${cluster_persistent_storage_type}"
cluster_persistent_bucket_names="${cluster_persistent_bucket_names}"
cluster_persistent_capacity_limit="${cluster_persistent_storage_capacity_limit}"
def_password="${temporary_password}"
deployment_name="${deployment_unique_name}"
ena_express="${ena_express}"
existing_deployment_name="${existing_deployment_unique_name}"
fault_domain_ids="${fault_domain_ids}"
float_ips="${floating_ips}"
functions_s3_prefix="${functions_s3_prefix}"
fqdn=${cluster_fqdn}
install_s3_prefix="${install_s3_prefix}"
instance_ids="${instance_ids}"
max_float_ips="${max_floating_ips}"
node_ips="${primary_ips}"
number_azs="${number_azs}"
replace_cluster="${replacement_cluster}"
s3_bucket="${bucket_name}"
s3_region="${bucket_region}"
serverIP=$(hostname -I | xargs)
target_node_count="${target_node_count}"
token=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
this_ec2=$(curl -H "X-aws-ec2-metadata-token: $token" -v http://169.254.169.254/latest/meta-data/instance-id)
version="${version}"
f_tput="${flash_tput}"
f_iops="${flash_iops}"
tun_refill_IOPS="${tun_refill_IOPS}"
tun_refill_Bps="${tun_refill_Bps}"
tun_EBS_BW="${tun_EBS_BW}"
tun_EC2_BW="${tun_EC2_BW}" 
tun_disk_count="${tun_disk_count}"

qqh="./qq --host ${node1_ip}"

#Update and grab the bash functions
if [[ ! -e "functions-cn-v14.sh" ]]; then
  aws s3 cp --region $s3_region s3://$s3_bucket/$functions_s3_prefix"functions-cn-v14.sh" ./functions-cn-v14.sh
fi
source functions-cn-v14.sh

#Check to make sure MQ is reachable
if [ $(chkurl "https://api.missionq.qumulo.com/"; echo $?) -eq 1 ]; then
  ssmput "last-run-status" "$region" "$deployment_name" "BOOTED. MQ reachable for metrics."
else
  ssmput "last-run-status" "$region" "$deployment_name" "BOOTED. MQ NOT reachable. Rectify and restart the provisioner."
  exit 1
fi

#Check to make sure Nexus is reachable
if [ $(chkurl "https://api.nexus.qumulo.com/"; echo $?) -eq 1 ]; then
  ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Nexus reachable."
else
  ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Nexus NOT reachable. Rectify and restart the provisioner."
  exit 1
fi

#Check for S3 gateway
traceroute -T -p 443 s3.$region.amazonaws.com > ./s3check.txt
m=0
last_line="no"
while IFS= read -r line; do 
    (( m = m + 1 ))
    if [ $m -gt 1 ]; then
        if [[ "$line" =~ ^.*"* * *".* ]]; then
            echo "Checking for S3 gateway - valid internal hop"
        elif [ "$last_line" == "yes" ]; then
            echo "Checking for S3 gateway - NO S3 GATEWAY"
            ssmput "last-run-status" "$region" "$deployment_name" "Missing S3 gateway!  Add an S3 gateway to your VPC and restart the provisioner."
            exit
        else
            last_line="yes"
        fi
    fi    
done < ./s3check.txt
echo "S3 gateway validated"
ssmput "last-run-status" "$region" "$deployment_name" "S3 gateway validated"

#If it's a replacement cluster use the previous cluster's admin password for subsequent operations and write that password to the new deployments secrets
if [ "$replace_cluster" == "true" ]; then
  existing_secrets_arn=$(ssmget "cluster-secrets-arn" "$region" "$existing_deployment_name")
  admin_password=$(getsecret "password" "$existing_secrets_arn" "$region" "false")
  aws secretsmanager put-secret-value --region $region --secret-id $cluster_secrets_arn --secret-string "{\"username\":\"admin\",\"password\":\"$admin_password\"}"  
else
  admin_password=$(getsecret "password" "$cluster_secrets_arn" "$region" "false")
fi

#Get the instance IDs
IFS=', ' read -r -a newIDs <<< "$instance_ids"

ssmput "last-run-status" "$region" "$deployment_name" "Checking quorum state and boot status"
ssmput "last-run-status" "$region" "$deployment_name" "Waiting for node 1 to run Qumulo Core. Package location: s3://$s3_bucket/$install_s3_prefix/$version/"

#Do a quick quorum check and wait on node boot cycles.
out_quorum=0
in_quorum=0
IFS=', ' read -r -a nodeIPs <<< "$node_ips"
IFS=', ' read -r -a faultIDs <<< "$fault_domain_ids"
for m in "${!nodeIPs[@]}"; do
  if [ $m -eq 1 ]; then
    ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Core running on node 1. Waiting for other nodes to run Qumulo Core."
  fi
  until [ $(chkurl "https://${nodeIPs[m]}:8000/v1/node/state" "NO"; echo $?) -eq 1 ]; do
    sleep 5
    echo "Waiting for ${nodeIPs[m]} to boot"
  done
  if [ $m -eq 0 ]; then
    getqq "${nodeIPs[m]}" "qq"
  fi

  quorum=$(./qq --host ${nodeIPs[m]} node_state_get)
  if [[ "$quorum" != *"ACTIVE"* ]]; then
    (( out_quorum = out_quorum + 1 ))
  else
    (( in_quorum = in_quorum + 1 ))
  fi
done

ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Core running on all nodes."

#Check the running software version and set the creation version if it is the first deployment
revision=$($qqh version | grep "revision_id")
current_version=${revision//[!0-9.]/}

ssmput "installed-version" "$region" "$deployment_name" "$current_version"

org_ver=$(ssmget "creation-version" "$region" "$deployment_name")

if [ "$org_ver" == "null" ]; then
  ssmput "creation-version" "$region" "$deployment_name" "$current_version"
  org_ver=$current_version
fi

#Check for version greater than 7.4.0 to support Qumulo Core with predictive cache and associated tunables
check_version=$(vercomp $current_version "7.4.0"; echo $?)
if [ $check_version -eq 2 ]; then
  echo "Qumulo Core >= 7.4.1"
else
  echo "Qumulo Core >= 7.4.1 is required."
  ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Core version >= 7.4.1 is required.  If this is a new deployment destroy it and redeploy with >= 7.4.1.  If this is an existing deployment contact Qumulo."
  exit 1
fi

#Check for version greater than 7.4.1 to support Qumulo Core single node clusters
check_version=$(vercomp $current_version "7.4.1"; echo $?)
if [ $check_version -eq 2 ]; then
  echo "Single node clusters supported"
elif [ ${#nodeIPs[@]} -eq 1 ]; then
  echo "Qumulo Core >= 7.4.2 is required for single node clusters."
  ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Core version >= 7.4.2 is required for single node clusters.  Destroy and redeploy with >= 7.4.2."
  exit 1
fi

#Check for version greater than 7.4.9 to support Qumulo Core DNS
qdns="false"
check_version=$(vercomp $current_version "7.4.9"; echo $?)
if [ $check_version -eq 2 ]; then
  echo "Qumulo DNS supported"
  if [[ ! -z "$fqdn" ]]; then  
    qdns="true"
  fi
elif [[ ! -z "$fqdn" ]]; then
  echo "Qumulo Core >= 7.5.0 is required for Qumulo DNS."
  ssmput "last-run-status" "$region" "$deployment_name" "Qumulo Core version >= 7.5.0 is required for Qumulo DNS.  Destroy and redeploy with >= 7.5.0."
  exit 1
fi

#Get the floating IPs
if [ "$float_ips" == "null" ]; then
  float_ips=""
fi
IFS=', ' read -r -a newFloatIPs <<< "$float_ips"
num_float_ips=${#newFloatIPs[@]}

#Get the bucket names and bucket URIs
IFS=', ' read -r -a bucketNames <<< "$cluster_persistent_bucket_names"
IFS=', ' read -r -a bucketURIs <<< "$cluster_persistent_bucket_uris"

###########Detailed quorum check for existing clusters before adding or removing nodes
add_nodes="false"
remove_nodes="false"

if [ $out_quorum -eq ${#nodeIPs[@]} ] && [ $in_quorum -eq 0 ]; then
  ssmput "last-run-status" "$region" "$deployment_name" "All nodes out of quorum, NEW CLUSTER"

  new_cluster="true"

  IFS=', ' read -r -a upgradeIPs <<< "$node_ips"

else
  allNodesList=()
  inNodesList=()
  outNodesList=()

  $qqh login -u admin -p $admin_password
  
  existingQuorum=$($qqh raw GET /v1/debug/quorum/details )

  allNodesRaw=$(echo $existingQuorum | grep -Po '"all_nodes":.*?\]')
  inNodesRaw=$(echo $existingQuorum | grep -Po '"in_nodes":.*?\]')
  outNodesRaw=$(echo $existingQuorum | grep -Po '"out_nodes":.*?\]')

  allNodes=${allNodesRaw/\"all_nodes\": [/}
  allNodes=$(echo $allNodes | tr -d "]")

  inNodes=${inNodesRaw/\"in_nodes\": [/}
  inNodes=$(echo $inNodes | tr -d "]")

  outNodes=${outNodesRaw/\"out_nodes\": [/}
  outNodes=$(echo $outNodes | tr -d "]")

  IFS=', ' read -r -a allNodesList <<< "$allNodes"
  IFS=', ' read -r -a inNodesList <<< "$inNodes"
  IFS=', ' read -r -a outNodesList <<< "$outNodes"

  if [ ${#outNodesList[@]} -gt 0 ]; then
    echo "One or more nodes out of quorum in existing cluster.  Rectify and restart the provisioner instance."
    ssmput "last-run-status" "$region" "$deployment_name" "One or more nodes out of quorum in existing cluster.  Rectify and restart the provisioner instance."
    exit 1
  else
    ssmput "last-run-status" "$region" "$deployment_name" "Cluster in full quorum, checking for node and/or bucket additions"
    new_cluster="false"

    IFS=', ' read -r -a newIPs <<< "$node_ips"
    IFS=', ' read -r -a oldIPs <<< $(ssmget "node-ips" "$region" "$deployment_name")
    for m in "${!newIPs[@]}"; do
      if [[ ! "${oldIPs[@]}" =~ "${newIPs[m]}" ]]; then
        upgradeIPs+=(${newIPs[m]})
      fi
    done

    if [[ ! -z "$float_ips" ]]; then
      IFS=', ' read -r -a newFIPs <<< "$float_ips"
    fi

    if [ ${#upgradeIPs[@]} -gt 0 ]; then
      revision=$(./qq --host ${upgradeIPs[0]} version | grep "revision_id")
      add_ver=${revision//[!0-9.]/}
      add_nodes="true"
      if [ "$current_version" != "$add_ver" ]; then
        ssmput "last-run-status" "$region" "$deployment_name" "Cluster is running ver=$current_version.  Can't add nodes running ver=$add_ver.  Update CloudFormation or Terraform with previous node count to remove these nodes. Exiting."
        exit 1
      fi
    fi

    if [ "$target_node_count" == "0" ]; then
      target_node_count=${#oldIPs[@]}
    fi

    if [ ${#oldIPs[@]} -gt $target_node_count ]; then
      remove_nodes="true"
    fi
  fi
fi

#########Check for existing bucket names and capacity limit
add_buckets="false"
increase_limit="false"

if [ "$replace_cluster" == "true" ]; then
  IFS=', ' read -r -a oldBucketNames <<< $(ssmget "bucket-names" "$region" "$existing_deployment_name")
  IFS=', ' read -r -a oldBucketURIs <<< $(ssmget "bucket-uris" "$region" "$existing_deployment_name")
  old_limit=$(ssmget "soft-capacity-limit" "$region" "$existing_deployment_name")  
else
  IFS=', ' read -r -a oldBucketNames <<< $(ssmget "bucket-names" "$region" "$deployment_name")
  IFS=', ' read -r -a oldBucketURIs <<< $(ssmget "bucket-uris" "$region" "$deployment_name")
  old_limit=$(ssmget "soft-capacity-limit" "$region" "$deployment_name")  
fi

if [ "$new_cluster" == "false" ] || [ "$replace_cluster" == "true" ]; then
  for m in "${!bucketNames[@]}"; do
    if [[ ! "${oldBucketNames[@]}" =~ "${bucketNames[m]}" ]]; then
      newBucketNames+=(${bucketNames[m]})
    fi
  done  

  for m in "${!bucketURIs[@]}"; do
    if [[ ! "${oldBucketURIs[@]}" =~ "${bucketURIs[m]}" ]]; then
      newBucketURIs+=(${bucketURIs[m]})
    fi
  done  

  if [ ${#newBucketNames[@]} -gt 0 ] && [ ${#newBucketURIs[@]} -gt 0 ]; then
    add_buckets="true"
  fi

  if [ $cluster_persistent_capacity_limit -gt $old_limit ] && [ "$add_buckets" == "false" ]; then
    increase_limit="true"
  fi
fi

############New Cluster Provisioning
if [ "$new_cluster" == "true" ] && [ "$replace_cluster" == "false" ]; then

  #Make sure buckets are empty
  for m in "${!bucketNames[@]}"; do
    contents=$(aws s3api list-objects-v2 --region $region --bucket ${bucketNames[m]} --max-items 1)
    if [[ "$contents" == *"Contents"* ]]; then
      echo "  **BUCKET NOT EMPTY, Exiting.  Empty bucket(s) and restart provisioner."
      ssmput "last-run-status" "$region" "$deployment_name" "Bucket ${bucketNames[m]} NOT EMPTY. Exiting. Empty all buckets and restart provisioner."
      exit 1
    else    
      echo "  **BUCKET ${bucketNames[m]} EMPTY"
    fi
  done

  case $cluster_persistent_storage_type in
    "hot_s3_std")
    product_type="ACTIVE_WITH_STANDARD_STORAGE"
    s3_type="Standard"
    cnq_type="Hot"
    ;;
    "hot_s3_int")
    product_type="ACTIVE_WITH_INTELLIGENT_STORAGE"   
    s3_type="Intelligent Tiering" 
    cnq_type="Hot"   
    ;;
    "cold_s3_ia") 
    product_type="ARCHIVE_WITH_IA_STORAGE"    
    s3_type="Infrequent Access"
    cnq_type="Cold"    
    ;;
    "cold_s3_gir")   
    product_type="ARCHIVE_WITH_GIR_STORAGE"     
    s3_type="Glacier Instant Retrieval"
    cnq_type="Cold"    
    ;;
  esac

  mod_bucket_URIs=()
  for m in "${!bucketURIs[@]}"; do
    mod_bucket_URIs+=("https://${bucketURIs[m]}/")
  done
  
  node_ips_fault_ids=()
  for m in "${!nodeIPs[@]}"; do
    node_ips_fault_ids+=("${nodeIPs[m]},${faultIDs[m]}")
  done

  ssmput "last-run-status" "$region" "$deployment_name" "Forming first quorum and configuring cluster"

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_DEBUG\", \"reset\": false}"
  echo "Quorom Formation Parameters"
  echo "eula_accepted: true"
  echo "cluster_name: $cluster_name"
  echo "node_ips_fault_ids: [${node_ips_fault_ids[@]}]"
  echo "fault_domain_ids: [$fault_domain_ids]"  
  echo "admin_password: $def_password"
  echo "host_instance_id: $def_password"
  echo "object_storage_uris: [${mod_bucket_URIs[@]}]"
  echo "usable_capacity_clamp: $cluster_persistent_capacity_limit"
  echo "pstore_class: $pstore_class"
  echo "product_type: $product_type"  

  $qqh create_object_backed_cluster --cluster-name $cluster_name --admin-password $def_password --accept-eula --host-instance-id $def_password --product-type $product_type --object-storage-uris ${mod_bucket_URIs[@]} --node-ips-and-fault-domains ${node_ips_fault_ids[@]} --usable-capacity-clamp $cluster_persistent_capacity_limit

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done
  echo "First Quorum formed"
  
  cluster_id=$($qqh node_state_get | grep "cluster_id" | tr -d '",')
  uuid=${cluster_id//"cluster_id: "/}

  ssmput "uuid" "$region" "$deployment_name" "$uuid"
  ssmput "node-ips" "$region" "$deployment_name" "$node_ips"
  ssmput "fault-domain-ids" "$region" "$deployment_name" "$fault_domain_ids"
  ssmput "instance-ids" "$region" "$deployment_name" "$instance_ids" 
  ssmput "creation-number-AZs" "$region" "$deployment_name" "$number_azs"
  ssmput "cluster-type" "$region" "$deployment_name" "CNQ=$cnq_type, S3=$s3_type"
  ssmput "soft-capacity-limit" "$region" "$deployment_name" "$cluster_persistent_capacity_limit"
  ssmput "bucket-uris" "$region" "$deployment_name" "$cluster_persistent_bucket_uris"
  ssmput "bucket-names" "$region" "$deployment_name" "$cluster_persistent_bucket_names"  
  ssmput "new-cluster" "$region" "$deployment_name" "false"  
  ssmput "last-run-status" "$region" "$deployment_name" "Setting cluster tunables if necessary"

  $qqh login -u admin -p $def_password

  calc_tun_refill_Bps=0

  if [ "$tun_refill_IOPS" != "0" ]; then
    $qqh raw PUT /v1/tunables/credit_accountant_io_refill_iops <<<"{\"configured_value\": \"$tun_refill_IOPS\"}"
  fi
  if [ "$tun_refill_Bps" != "0" ] && [ "$tun_disk_count" != "0" ]; then
    calc_tun_refill_Bps=$(( $tun_refill_Bps * 1000 * 1000 / 4096 ))
    $qqh raw PUT /v1/tunables/credit_accountant_th_refill_blocks_per_second <<<"{\"configured_value\": \"$calc_tun_refill_Bps\"}" 
  fi
  if [ "$tun_EBS_BW" != "0" ]; then
    $qqh raw PUT /v1/tunables/vm_disk_throughput_model_megabytes_per_second <<<"{\"configured_value\": \"$tun_EBS_BW\"}"
  fi
  if [ "$tun_EC2_BW" != "0" ]; then
    $qqh raw PUT /v1/tunables/vm_network_saturation_model_threshold_megabytes_per_second <<<"{\"configured_value\": \"$tun_EC2_BW\"}"
  fi
  
  $qqh raw POST /v1/debug/quorum/abandon-series </dev/null

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Bouncing quorum to apply tunables"
  done
  echo "Second quorum formed with tunables"

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_INFO\", \"reset\": false}"

  ssmput "tunables" "$region" "$deployment_name" "refill_IOPS=$tun_refill_IOPS, refill_Bps=$calc_tun_refill_Bps, EBS_BW=$tun_EBS_BW, EC2_BW=$tun_EC2_BW"

  $qqh audit_set_cloudwatch_config --enable --log-group-name /qumulo/$deployment_name-audit-log --region $region
  if [[ ! -z "$float_ips" ]]; then
    $qqh network_mod_network --network-id 1 --floating-ip-ranges $float_ips
    if [ "$qdns" == "true" ]; then
      $qqh authoritative_dns_modify_settings --enable --fqdn $fqdn.    
    fi
    ssmput "float-ips" "$region" "$deployment_name" "$float_ips"
    ssmput "number-float-ips" "$region" "$deployment_name" "$num_float_ips"  
    ssmput "max-float-ips" "$region" "$deployment_name" "$max_float_ips"      
  fi
  $qqh change_password -o $def_password -p $admin_password

###########Replacement cluster provisioning
elif [ "$new_cluster" == "true" ] && [ "$replace_cluster" == "true" ]; then
  node_ips_fault_ids=()
  for m in "${!nodeIPs[@]}"; do
    node_ips_fault_ids+=("${nodeIPs[m]},${faultIDs[m]}")
  done  
  
  IFS=', ' read -r -a existingIPs <<< $(ssmget "node-ips" "$region" "$existing_deployment_name")
  IFS=', ' read -r -a existingIDs <<< $(ssmget "instance-ids" "$region" "$existing_deployment_name")

  existing_number_azs=$(ssmget "creation-number-AZs" "$region" "$existing_deployment_name")

  #Check to make sure the number of floating IPs in the previous cluster can be supported by the new cluster's instance type if SAZ
  if [[ "$number_azs" -eq "1" ]] && [[ "$existing_number_azs" -eq "1" ]]; then
    existing_num_float_ips=$(ssmget "number-float-ips" "$region" "$existing_deployment_name")

    if [[ "$existing_num_float_ips" -gt "$max_float_ips" ]]; then
      echo "Error, the EC2 instance type chosen for the replacement cluster can't support the number of floating IPs in the existing cluster.  Destroy this deployment and redeploy."
      ssmput "last-run-status" "$region" "$deployment_name" "Error, the EC2 instance type chosen for the replacement cluster can't support the number of floating IPs in the existing cluster.  Destroy this deployment and redeploy."
      exit 1
    fi
  fi

  ssmput "last-run-status" "$region" "$deployment_name" "Detected CLUSTER REPLACE.  Adding new security group to existing nodes and detecting node IDs."

  existingSGIDs=$(aws ec2 describe-instances --region $region --instance-ids ${existingIDs[0]} --query "Reservations[].Instances[].SecurityGroups[].GroupId[]" --output text)
  existingSGIDs+=" $cluster_sg_id"

  #Get Qumulo node_ids from existing cluster
  for m in "${!existingIPs[@]}"; do
    qnodeState=$(./qq --host ${existingIPs[m]} node_state_get)
    qnodeID=$(echo "$qnodeState" | grep "node_id")
    qid=${qnodeID//[!0-9.]/}
    existingNodeIDs+=("$qid ")
    echo "node_id=$qid"

    aws ec2 modify-instance-attribute --region $region --instance-id ${existingIDs[m]} --groups $existingSGIDs
  done   

  ssmput "last-run-status" "$region" "$deployment_name" "Detected CLUSTER REPLACE.  Adding new nodes to quorum and removing existing nodes from quorum."

  #now call for replace
  ./qq --host ${existingIPs[0]} login -u admin -p $admin_password
  if [[ "$number_azs" -gt "1" ]]; then
    if [ "$qdns" == "true" ]; then
      ./qq --host ${existingIPs[0]} authoritative_dns_modify_settings --disable       
    fi
    ./qq --host ${existingIPs[0]} network_mod_network --network-id 1 --floating-ip-ranges ""
  fi
  ./qq --host ${existingIPs[0]} raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_DEBUG\", \"reset\": false}"
  
  # start MCS-2084: add retry logic for modify_object_backed_cluster_membership to avoid race condition
  retries=20
  count=1
  success=false
  echo "Attempting to update cluster membership (max $retries retries with exponential backoff)"
  until ./qq --host ${existingIPs[0]} modify_object_backed_cluster_membership --node-ips-and-fault-domains ${node_ips_fault_ids[@]} --batch
  do
    if [ $count -ge $retries ]; then
      echo "WARN: membership update failed after $retries attempts"
      break
    fi
    sleep_duration=$((10 * 2 ** (count - 1)))
    echo "Attempt $count/$retries failed. Retrying in ${sleep_duration}s..."
    sleep $sleep_duration
    count=$((count + 1))
  done
  [ $count -lt $retries ] && echo "Cluster membership updated successfully on attempt $count"
  # end MCS-2084
  
  ssmput "last-run-status" "$region" "$deployment_name" "Detected CLUSTER REPLACE.  Waiting for new quorum."

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done
  echo "New Quorum formed"
  
  sleep 1

  ssmput "last-run-status" "$region" "$deployment_name" "Detected CLUSTER REPLACE.  New quorum formed, validating node replacement."
  
  allNodesList=()
  inNodesList=()
  outNodesList=()

  until [ ${#allNodesList[@]} -eq ${#nodeIPs[@]} ] && [ ${#inNodesList[@]} -eq ${#nodeIPs[@]} ] && [ ${#outNodesList[@]} -eq 0 ]; do
    newQuorum=$($qqh raw GET /v1/debug/quorum/details )

    allNodesRaw=$(echo $newQuorum | grep -Po '"all_nodes":.*?\]')
    inNodesRaw=$(echo $newQuorum | grep -Po '"in_nodes":.*?\]')
    outNodesRaw=$(echo $newQuorum | grep -Po '"out_nodes":.*?\]')

    allNodes=${allNodesRaw/\"all_nodes\": [/}
    allNodes=$(echo $allNodes | tr -d "]")

    inNodes=${inNodesRaw/\"in_nodes\": [/}
    inNodes=$(echo $inNodes | tr -d "]")

    outNodes=${outNodesRaw/\"out_nodes\": [/}
    outNodes=$(echo $outNodes | tr -d "]")

    IFS=', ' read -r -a allNodesList <<< "$allNodes"
    IFS=', ' read -r -a inNodesList <<< "$inNodes"
    IFS=', ' read -r -a outNodesList <<< "$outNodes"

    sleep 10
  done

  for m in "${!allNodesList[@]}"; do
    if [[ "${existingNodeIDs[@]}" =~ "${allNodesList[m]}" ]]; then
      echo "  **Old Node: ${allNodesList[m]} not removed from quorum.  Slack Support."
      exit 1
    fi
  done

  ssmput "last-run-status" "$region" "$deployment_name" "Detected CLUSTER REPLACE: New quorum formed with ${#nodeIPs[@]} new nodes as requested."

  existing_cluster_type=$(ssmget "cluster-type" "$region" "$existing_deployment_name")

  cluster_id=$($qqh node_state_get | grep "cluster_id" | tr -d '",')
  uuid=${cluster_id//"cluster_id: "/}

  ssmput "uuid" "$region" "$deployment_name" "$uuid"
  ssmput "node-ips" "$region" "$deployment_name" "$node_ips"
  ssmput "fault-domain-ids" "$region" "$deployment_name" "$fault_domain_ids"
  ssmput "instance-ids" "$region" "$deployment_name" "$instance_ids" 
  ssmput "creation-number-AZs" "$region" "$deployment_name" "$number_azs"
  ssmput "cluster-type" "$region" "$deployment_name" "$existing_cluster_type"
  ssmput "soft-capacity-limit" "$region" "$deployment_name" "$cluster_persistent_capacity_limit"
  ssmput "bucket-uris" "$region" "$deployment_name" "$cluster_persistent_bucket_uris"
  ssmput "bucket-names" "$region" "$deployment_name" "$cluster_persistent_bucket_names"

  $qqh login -u admin -p $admin_password

  if [[ "$number_azs" -eq "1" ]]; then
    $qqh network_mod_network --network-id 1 --floating-ip-ranges $float_ips  
    if [ "$qdns" == "true" ]; then
      $qqh authoritative_dns_modify_settings --enable --fqdn $fqdn.      
    fi
    ssmput "float-ips" "$region" "$deployment_name" "$float_ips"
    ssmput "number-float-ips" "$region" "$deployment_name" "$num_float_ips"
    ssmput "max-float-ips" "$region" "$deployment_name" "$max_float_ips"  
  else
    ssmput "float-ips" "$region" "$deployment_name" "null"
    ssmput "number-float-ips" "$region" "$deployment_name" "null"
    ssmput "max-float-ips" "$region" "$deployment_name" "null"  
  fi
  ssmput "new-cluster" "$region" "$deployment_name" "false"  
  ssmput "last-run-status" "$region" "$deployment_name" "Setting cluster tunables if necessary"

  calc_tun_refill_Bps=0

  if [ "$tun_refill_IOPS" != "0" ]; then
    $qqh raw PUT /v1/tunables/credit_accountant_io_refill_iops <<<"{\"configured_value\": \"$tun_refill_IOPS\"}"
  fi
  if [ "$tun_refill_Bps" != "0" ] && [ "$tun_disk_count" != "0" ]; then
    calc_tun_refill_Bps=$(( $tun_refill_Bps * 1000 * 1000 / 4096 ))
    $qqh raw PUT /v1/tunables/credit_accountant_th_refill_blocks_per_second <<<"{\"configured_value\": \"$calc_tun_refill_Bps\"}" 
  fi
  if [ "$tun_EBS_BW" != "0" ]; then
    $qqh raw PUT /v1/tunables/vm_disk_throughput_model_megabytes_per_second <<<"{\"configured_value\": \"$tun_EBS_BW\"}"
  fi
  if [ "$tun_EC2_BW" != "0" ]; then
    $qqh raw PUT /v1/tunables/vm_network_saturation_model_threshold_megabytes_per_second <<<"{\"configured_value\": \"$tun_EC2_BW\"}"
  fi

  $qqh raw POST /v1/debug/quorum/abandon-series </dev/null

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Bouncing quorum to apply tunables"
  done
  echo "Second quorum formed with tunables"

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_INFO\", \"reset\": false}"

  ssmput "tunables" "$region" "$deployment_name" "refill_IOPS=$tun_refill_IOPS, refill_Bps=$calc_tun_refill_Bps, EBS_BW=$tun_EBS_BW, EC2_BW=$tun_EC2_BW"

##########Add nodes to existing cluster
elif [ "$add_nodes" == "true" ] && [ "$replace_cluster" != "true" ]; then
  ssmput "last-run-status" "$region" "$deployment_name" "Quorum already exists, adding nodes to cluster"

  $qqh login -u admin -p $admin_password

  if [[ ! -z "$float_ips" ]]; then
    delim=""
    halfFloatIPs=""
    for m in "${!newFIPs[@]}"; do
      if [ $m -lt 40 ]; then
        halfFloatIPs="$halfFloatIPs$delim${newFIPs[m]}"
        delim=", "
      fi
    done
    $qqh network_mod_network --network-id 1 --floating-ip-ranges $halfFloatIPs
  fi

  node_ips_fault_ids=()
  for m in "${!nodeIPs[@]}"; do
    node_ips_fault_ids+=("${nodeIPs[m]},${faultIDs[m]}")
  done

  $qqh modify_object_backed_cluster_membership --node-ips-and-fault-domains ${node_ips_fault_ids[@]} --batch

  until ./qq --host ${upgradeIPs[0]} node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done
  echo "Quorum formed"
  ssmput "node-ips" "$region" "$deployment_name" "$node_ips"
  ssmput "fault-domain-ids" "$region" "$deployment_name" "$fault_domain_ids"  
  ssmput "instance-ids" "$region" "$deployment_name" "$instance_ids" 

  if [[ ! -z "$float_ips" ]]; then
    $qqh network_mod_network --network-id 1 --floating-ip-ranges $float_ips
    if [ "$qdns" == "true" ]; then
      $qqh authoritative_dns_modify_settings --enable --fqdn $fqdn.      
    fi
    ssmput "float-ips" "$region" "$deployment_name" "$float_ips"
    ssmput "number-float-ips" "$region" "$deployment_name" "$num_float_ips"  
    ssmput "max-float-ips" "$region" "$deployment_name" "$max_float_ips"            
  fi 
fi

##########Remove nodes from existing cluster
if [ "$new_cluster" != "true" ] && [ "$remove_nodes" == "true" ] && [ "$replace_cluster" != "true" ]; then
  ssmput "last-run-status" "$region" "$deployment_name" "Quorum already exists, removing nodes from cluster."

  #Get Qumulo node_ids from existing cluster
  for m in "${!nodeIPs[@]}"; do
    qnodeState=$(./qq --host ${nodeIPs[m]} node_state_get)
    qnodeID=$(echo "$qnodeState" | grep "node_id")
    qid=${qnodeID//[!0-9.]/}
    existingNodeIDs+=("$qid ")
    echo "node_id=$qid"
  done   

  remaining_nodeIPs=("${nodeIPs[@]:0:${target_node_count}}")
  remaining_faultIDs=("${faultIDs[@]:0:${target_node_count}}")
  remaining_instanceIDs=("${newIDs[@]:0:${target_node_count}}")
  removed_nodeIDs=("${existingNodeIDs[@]:${target_node_count}:${#nodeIPs[@]}}")

  node_ips_fault_ids=()
  for m in "${!remaining_nodeIPs[@]}"; do
    node_ips_fault_ids+=("${remaining_nodeIPs[m]},${remaining_faultIDs[m]}")
  done

  $qqh login -u admin -p $admin_password

  $qqh modify_object_backed_cluster_membership --node-ips-and-fault-domains ${node_ips_fault_ids[@]} --batch

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done
  echo "Quorum formed"

  ssmput "last-run-status" "$region" "$deployment_name" "New quorum formed, validating node removal."
  
  allNodesList=()
  inNodesList=()
  outNodesList=()

  until [ ${#allNodesList[@]} -eq ${#remaining_nodeIPs[@]} ] && [ ${#inNodesList[@]} -eq ${#remaining_nodeIPs[@]} ] && [ ${#outNodesList[@]} -eq 0 ]; do
    newQuorum=$($qqh raw GET /v1/debug/quorum/details )

    allNodesRaw=$(echo $newQuorum | grep -Po '"all_nodes":.*?\]')
    inNodesRaw=$(echo $newQuorum | grep -Po '"in_nodes":.*?\]')
    outNodesRaw=$(echo $newQuorum | grep -Po '"out_nodes":.*?\]')

    allNodes=${allNodesRaw/\"all_nodes\": [/}
    allNodes=$(echo $allNodes | tr -d "]")

    inNodes=${inNodesRaw/\"in_nodes\": [/}
    inNodes=$(echo $inNodes | tr -d "]")

    outNodes=${outNodesRaw/\"out_nodes\": [/}
    outNodes=$(echo $outNodes | tr -d "]")

    IFS=', ' read -r -a allNodesList <<< "$allNodes"
    IFS=', ' read -r -a inNodesList <<< "$inNodes"
    IFS=', ' read -r -a outNodesList <<< "$outNodes"

    sleep 10
  done

  for m in "${!allNodesList[@]}"; do
    if [[ "${removedNodeIDs[@]}" =~ "${allNodesList[m]}" ]]; then
      echo "  **Old Node: ${allNodesList[m]} not removed from quorum.  Slack Support."
      exit 1
    fi
  done

  ssmput "last-run-status" "$region" "$deployment_name" "New quorum formed with ${#remaining_nodeIPs[@]} node(s) as requested."

  node_ips=$(IFS=', ' ; echo "${remaining_nodeIPs[*]}")
  fault_domain_ids=$(IFS=', ' ; echo "${remaining_faultIDs[*]}")
  instance_ids=$(IFS=', ' ; echo "${remaining_instanceIDs[*]}")

  ssmput "node-ips" "$region" "$deployment_name" "$node_ips"
  ssmput "fault-domain-ids" "$region" "$deployment_name" "$fault_domain_ids"
  ssmput "instance-ids" "$region" "$deployment_name" "$instance_ids" 

  if [[ ! -z "$float_ips" ]]; then
    $qqh network_mod_network --network-id 1 --floating-ip-ranges $float_ips
    if [ "$qdns" == "true" ]; then
      $qqh authoritative_dns_modify_settings --enable --fqdn $fqdn.      
    fi
    ssmput "float-ips" "$region" "$deployment_name" "$float_ips"
    ssmput "number-float-ips" "$region" "$deployment_name" "$num_float_ips"  
    ssmput "max-float-ips" "$region" "$deployment_name" "$max_float_ips"      
  fi
fi

##########Update Instance Tags
ssmput "last-run-status" "$region" "$deployment_name" "Updating cluster tags"

for m in "${!newIDs[@]}"; do
  (( n = m + 1 ))
  qnodeState=$(./qq --host ${nodeIPs[m]} node_state_get)
  qnodeID=$(echo "$qnodeState" | grep "node_id")
  qid=${qnodeID//[!0-9]/}

  aws ec2 create-tags --region $region --resources ${newIDs[m]} --tags "Key=Name,Value=$deployment_name-node-$n-$qid"  
done

###########ENA Express - only supported on certain instance types and sizes and can create issues with instance type/size changes if not done with cluster replace
if [ "$new_cluster" == "true" ] || [ "$replace_cluster" == "true" ] || [ "$add_nodes" == "true" ]; then
  if [ "$ena_express" == "yes" ]; then
    ssmput "last-run-status" "$region" "$deployment_name" "Enabling ENA Express"
    for m in "${!newIDs[@]}"; do
      ec2Eni=$(aws ec2 describe-instances --region $region --instance-ids ${newIDs[m]} --query "Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId" --output text)
      aws ec2 modify-network-interface-attribute --network-interface-id $ec2Eni  --ena-srd-specification "EnaSrdEnabled=true"
    done
  else
    echo "$ec2Type doesn't support ENA Express"
  fi
fi

##########Add Buckets
if [ "$add_buckets" == "true" ]; then
  for m in "${!newBucketNames[@]}"; do
    contents=$(aws s3api list-objects-v2 --region $region --bucket ${newBucketNames[m]} --max-items 1)
    if [[ "$contents" == *"Contents"* ]]; then
      echo "  **BUCKET NOT EMPTY, Exiting.  Empty bucket(s) and restart provisioner."
      ssmput "last-run-status" "$region" "$deployment_name" "Bucket ${newBucketNames[m]} NOT EMPTY. Exiting. Empty the new buckets you wish to add and restart provisioner."
      exit 1
    else    
      echo "  **BUCKET ${newBucketNames[m]} EMPTY"
    fi
  done

  ssmput "last-run-status" "$region" "$deployment_name" "Adding buckets for persistent storage & increasing soft capacity limit"

  mod_bucket_URIs=()
  for m in "${!newBucketURIs[@]}"; do
    mod_bucket_URIs+=("https://${newBucketURIs[m]}/")
  done
  
  $qqh login -u admin -p $admin_password

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_DEBUG\", \"reset\": false}"
  echo "Bucket Add Parameters"
  echo "object_storage_uris: [${newBucketURIs[@]}]"
  echo "usable_capacity_clamp: $cluster_persistent_capacity_limit"

  $qqh add_object_storage_uris --uris ${mod_bucket_URIs[@]}

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done

  allNodesList=()
  inNodesList=()
  outNodesList=()

  until [ ${#allNodesList[@]} -eq ${#nodeIPs[@]} ] && [ ${#inNodesList[@]} -eq ${#nodeIPs[@]} ] && [ ${#outNodesList[@]} -eq 0 ]; do
    newQuorum=$($qqh raw GET /v1/debug/quorum/details )

    allNodesRaw=$(echo $newQuorum | grep -Po '"all_nodes":.*?\]')
    inNodesRaw=$(echo $newQuorum | grep -Po '"in_nodes":.*?\]')
    outNodesRaw=$(echo $newQuorum | grep -Po '"out_nodes":.*?\]')

    allNodes=${allNodesRaw/\"all_nodes\": [/}
    allNodes=$(echo $allNodes | tr -d "]")

    inNodes=${inNodesRaw/\"in_nodes\": [/}
    inNodes=$(echo $inNodes | tr -d "]")

    outNodes=${outNodesRaw/\"out_nodes\": [/}
    outNodes=$(echo $outNodes | tr -d "]")

    IFS=', ' read -r -a allNodesList <<< "$allNodes"
    IFS=', ' read -r -a inNodesList <<< "$inNodes"
    IFS=', ' read -r -a outNodesList <<< "$outNodes"

    sleep 10
  done

  if [ ${#outNodesList[@]} -gt 0 ]; then
    ehco "One or more nodes out of quorum in existing cluster.  Rectify and restart the provisioner instance."
    ssmput "last-run-status" "$region" "$deployment_name" "One or more nodes out of quorum in existing cluster.  Rectify and restart the provisioner instance."
    exit 1
  else
    ssmput "last-run-status" "$region" "$deployment_name" "Buckets added, cluster in full quorum, checking for soft-capacity-limit increase."
  fi

  ssmput "bucket-uris" "$region" "$deployment_name" "$cluster_persistent_bucket_uris"
  ssmput "bucket-names" "$region" "$deployment_name" "$cluster_persistent_bucket_names"   

  $qqh capacity_clamp_set --clamp $cluster_persistent_capacity_limit

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done
  echo "Soft capacity limit set and Quorum formed"

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_INFO\", \"reset\": false}"

  ssmput "soft-capacity-limit" "$region" "$deployment_name" "$cluster_persistent_capacity_limit" 
fi

###########Increase Soft Capacity Limit
if [ "$increase_limit" == "true" ]; then
  ssmput "last-run-status" "$region" "$deployment_name" "Increasing soft capacity limit"

  $qqh login -u admin -p $admin_password

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_DEBUG\", \"reset\": false}"
  echo "usable_capacity_clamp: $cluster_persistent_capacity_limit"

  $qqh capacity_clamp_set --clamp $cluster_persistent_capacity_limit

  until $qqh node_state_get | grep -q "ACTIVE"; do
    sleep 5
    echo "Waiting for Quorum"
  done
  echo "Soft capacity limit increased and Quorum formed"

  $qqh raw PUT /v1/conf/log/module/%2F <<<"{\"level\": \"QM_LOG_INFO\", \"reset\": false}"

  ssmput "soft-capacity-limit" "$region" "$deployment_name" "$cluster_persistent_capacity_limit"
fi

###########Tag EBS Volumes
ssmput "last-run-status" "$region" "$deployment_name" "Tagging EBS volumes & updating EBS IOPS/Tput if applicable"
tagvols "newIDs" "$region" "$deployment_name" "$f_iops" "$f_tput"

ssmput "last-run-status" "$region" "$deployment_name" "Shutting down provisioning instance"
