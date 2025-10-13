chkurl () {
  local url=$1 no_sec=$2
  local k

  if [[ -n "$no_sec" ]]; then
    k="k"
  fi

  http_code=$(curl -sL$k -w "%{http_code}\\n" "$url" -o /dev/null --connect-timeout 10 --retry 3 --retry-delay 5 --max-time 60)

  if [ "$http_code" == "200" ] || [ "$http_code" == "403" ]; then
      return 1
  else
      return 0
  fi
}

getqq () {
  local ip=$1 file_name=$2

  wget --no-check-certificate -O $file_name https://$ip/static/qq
  chmod 777 ./$file_name
}

getsecret () {
  local filter=$1 arn=$2 region=$3 obscure=$4
  local secret
  
  if [ "$obscure" == "true" ]; then
    secret=$(aws secretsmanager get-secret-value --region $region --query "SecretString" --output text --secret-id $arn | jq -r .$filter | xxd -p -r)
  else
    secret=$(aws secretsmanager get-secret-value --region $region --query "SecretString" --output text --secret-id $arn | jq -r .$filter)
  fi
  echo $secret
}

ssmput () {
  local key=$1 region=$2 stackname=$3 value=$4
  aws ssm put-parameter --region $region --type SecureString --overwrite --name "/qumulo/$stackname/$key" --value "$value"
}

ssmget () {
  local key=$1 region=$2 stackname=$3
  local output
  output=$(aws ssm get-parameter --region $region --with-decryption --output text --name "/qumulo/$stackname/$key" --query "Parameter.Value")
  echo $output
}

stackprotect () {
  local enable=$1 region=$2 stackname=$3

  if [ "$enable" == "NO" ]; then
    aws cloudformation update-termination-protection --region $region --stack-name $stackname --no-enable-termination-protection
  else
    aws cloudformation update-termination-protection --region $region --stack-name $stackname --enable-termination-protection
  fi
}

ec2protect () {
  local enable=$1 region=$2 instance=$3
  if [ "$enable" == "NO" ]; then
    aws ec2 modify-instance-attribute --region $region --instance-id $instance --no-disable-api-termination
  else
    aws ec2 modify-instance-attribute --region $region --instance-id $instance --disable-api-termination
  fi    
}

setstackpolicy () {
  local region=$1 stackname=$2 policyfile=$3
  local stack_status nodeStackPhyIds m

  stack_status=$(aws cloudformation describe-stacks --region $region --stack-name $stackname --query Stacks[].StackStatus --output text)

  while [ "$stack_status" != "CREATE_COMPLETE" ] && [ "$stack_status" != "UPDATE_COMPLETE" ]; do
    echo $stack_status
    echo "CF Stack Not Complete: $stackname. Waiting on Stack to complete."
    sleep 15
    stack_status=$(aws cloudformation describe-stacks --region $region --stack-name $stackname --query Stacks[].StackStatus --output text)
  done

  nodeStackPhyIds=($(aws cloudformation describe-stack-resources --region $region --stack-name $stackname --query 'StackResources[?contains(LogicalResourceId, `NODESTACK`) == `true`].PhysicalResourceId' --output text))

  for m in "${!nodeStackPhyIds[@]}"; do
    aws cloudformation set-stack-policy --region $region --stack-name ${nodeStackPhyIds[m]} --stack-policy-body file://$policyfile
  done
}

vercomp () {        
  if [[ $1 == $2 ]]; then
    return 0
  fi

  local IFS=.
  local i v1=($1) v2=($2)

  for ((i=${#v1[@]}; i<${#v2[@]}; i++)); do
    v1[i]=0
  done
  for ((i=0; i<${#v1[@]}; i++)); do
    if [[ -z ${v2[i]} ]]; then
      v2[i]=0
    fi
    if ((10#${v1[i]} > 10#${v2[i]})); then
      return 2
    fi
    if ((10#${v1[i]} < 10#${v2[i]})); then
      return 1
    fi
  done
  return 0
}

tagvols () {
  local id_list_name=$1[@] region=$2 stack_name=$3 iops=$4 tput=$5
  local m id_list bootIDs=() gp2IDs=() gp3IDs=() io2IDs=() gp2IDs_groomed=() gp3IDs_groomed=() dkvIDs=()

  id_list=("${!id_list_name}")

  for m in "${!id_list[@]}"; do 
    bootIDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/sda*" --query "Volumes[].VolumeId" --out "text"))  

    dkvIDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/x*" "Name=size, Values=4" --query "Volumes[].VolumeId" --out "text"))

    rgp2IDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/x*" "Name=size, Values=1024" "Name=volume-type, Values=gp2" --query "Volumes[].VolumeId" --out "text"))

    gp2IDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/x*" "Name=volume-type, Values=gp2" --query "Volumes[].VolumeId" --out "text"))  

    rgp3IDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/x*" "Name=size, Values=1024" "Name=volume-type, Values=gp3" --query "Volumes[].VolumeId" --out "text"))

    gp3IDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/x*" "Name=volume-type, Values=gp3" --query "Volumes[].VolumeId" --out "text"))

    io2IDs+=($(aws ec2 describe-volumes --region $region --filter "Name=attachment.instance-id, Values=${id_list[m]}" "Name=attachment.device, Values=/dev/x*" "Name=volume-type, Values=io2" --query "Volumes[].VolumeId" --out "text"))
  done

  if [ ${#bootIDs[@]} -gt 0 ]; then
    aws ec2 create-tags --region $region --resources ${bootIDs[@]} --tags "Key=Name,Value=$stack_name-boot"
  fi

  if [ ${#dkvIDs[@]} -gt 0 ]; then
    aws ec2 create-tags --region $region --resources ${dkvIDs[@]} --tags "Key=Name,Value=$stack_name-dkv"
  fi

  if [ ${#gp2IDs[@]} -gt 0 ]; then
    for m in "${!gp2IDs[@]}"; do
      if [[ ! "${dkvIDs[@]}" =~ "${gp2IDs[m]}" ]] && [[ ! "${rgp2IDs[@]}" =~ "${gp2IDs[m]}" ]]; then
        gp2IDs_groomed+=(${gp2IDs[m]})
      fi
    done
    if [ ${#gp2IDs_groomed[@]} -gt 0 ]; then    
      aws ec2 create-tags --region $region --resources ${gp2IDs_groomed[@]} --tags "Key=Name,Value=$stack_name-gp2"
    fi
    if [ ${#rgp2IDs_groomed[@]} -gt 0 ]; then    
      aws ec2 create-tags --region $region --resources ${rgp2IDs[@]} --tags "Key=Name,Value=$stack_name-gp2"
    fi    
  fi
  
  if [ ${#gp3IDs[@]} -gt 0 ]; then
    for m in "${!gp3IDs[@]}"; do
      if [[ ! "${dkvIDs[@]}" =~ "${gp3IDs[m]}" ]] && [[ ! "${rgp3IDs[@]}" =~ "${gp3IDs[m]}" ]]; then
        gp3IDs_groomed+=(${gp3IDs[m]})
      fi
    done

    if [ ${#gp3IDs_groomed[@]} -gt 0 ]; then    
      aws ec2 create-tags --region $region --resources ${gp3IDs_groomed[@]} --tags "Key=Name,Value=$stack_name-gp3"
      if [[ "$iops" -gt "3000" ]] || [[ "$tput" -gt "125" ]]; then
        for m in "${!gp3IDs_groomed[@]}"; do
          if [ ! $(aws ec2 modify-volume --region $region --volume-id ${gp3IDs_groomed[m]} --volume-type gp3 --iops $iops --throughput $tput | grep -q "error") ]; then
	          echo "Can't change gp3 IOPS/Tput at this time."
          fi        
        done
      fi         
    fi

    if [ ${#rgp3IDs[@]} -gt 0 ]; then    
      aws ec2 create-tags --region $region --resources ${rgp3IDs[@]} --tags "Key=Name,Value=$stack_name-gp3"
      for m in "${!rgp3IDs[@]}"; do
        if [ ! $(aws ec2 modify-volume --region $region --volume-id ${rgp3IDs[m]} --volume-type gp3 --iops 12500 --throughput 525 | grep -q "error") ]; then
	        echo "Can't change gp3 IOPS/Tput at this time."
        fi        
      done
    fi    
  fi  
  
  if [ ${#io2IDs[@]} -gt 0 ]; then    
    aws ec2 create-tags --region $region --resources ${io2IDs[@]} --tags "Key=Name,Value=$stack_name-io2"
    for m in "${!io2IDs[@]}"; do
      if [ ! $(aws ec2 modify-volume --region $region --volume-id ${io2IDs[m]} --volume-type io2 --iops $iops | grep -q "error") ]; then
        echo "Can't change io2 IOPS at this time."
      fi        
    done         
  fi  
}
