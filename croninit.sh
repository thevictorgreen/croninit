#!/bin/bash


# Log Output To A File
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/root/.croninit/log.out 2>&1

# QUERY LOCAL TAGS
function query_tags() {
index=0
value=
for key in $( aws ec2 describe-instances --instance-id $( curl http://169.254.169.254/latest/meta-data/instance-id ) --region us-east-1 | jq -r '.Reservations[].Instances[].Tags[].Key' )
do
      if [[ "$key" == "$1" ]]
      then
           value=$( aws ec2 describe-instances --instance-id $( curl http://169.254.169.254/latest/meta-data/instance-id ) --region us-east-1 | jq --arg jqindex $index -r '.Reservations[].Instances[].Tags[$jqindex|tonumber].Value' )
      else
           ((index++))
      fi
done
echo $value
}


# QUERY EXTERNAL TAGS
function query_tags_external() {
index=0
value=
for key in $( aws ec2 describe-instances --instance-id $( echo $2 ) --region us-east-1 | jq -r '.Reservations[].Instances[].Tags[].Key' )
do
      if [[ "$key" == "$1" ]]
      then
           value=$( aws ec2 describe-instances --instance-id $( echo $2 ) --region us-east-1 | jq --arg jqindex $index -r '.Reservations[].Instances[].Tags[$jqindex|tonumber].Value' )
      else
           ((index++))
      fi
done
echo $value
}


# @reboot /root/.croninit/croninit.sh
if [[ ! -f "/root/.croninit/init.cfg" ]]
then
      # IAM Profile May have not been applied yet
      # Don't move forward until it is
      # We need to query values from the tags
      echo "getting domain"
      domain=
      while [[ -z "$domain" ]]
      do
        domain=$( query_tags domain )
        sleep 10
      done
      echo "received domain $domain"

      # Get Parameters From Remaining Tags
      echo "Getting remaining parameters from tags"
      forwardzoneid=$( query_tags forwardzoneid )
      reversezoneid=$( query_tags reversezoneid )
      is_ipa_server=$( query_tags is-ipa-server )
      join_ipa=$( query_tags join-ipa)
      join_chef=$( query_tags join-chef)
      echo "received remaining parameters $forwardzoneid $reversezoneid $is_ipa_server $join_ipa $join_chef"

      # Generate Hostname
      echo "generating hostname"
      LOCAL_NAME=$( echo rhw$(tr -cd "[:digit:]" < /dev/urandom | fold -w2 | head -n1).${domain} )
      echo $LOCAL_NAME

      # Grab private IP Address
      echo "grabbing local ip"
      LOCAL_IPV4=$( curl http://169.254.169.254/latest/meta-data/local-ipv4 )
      echo "have local ip $LOCAL_IPV4"

      # Create Reverse Hostname
      echo "creating reverse hostname"
      OCTET1=$( echo $LOCAL_IPV4 | cut -d. -f1 )
      OCTET2=$( echo $LOCAL_IPV4 | cut -d. -f2 )
      OCTET3=$( echo $LOCAL_IPV4 | cut -d. -f3 )
      OCTET4=$( echo $LOCAL_IPV4 | cut -d. -f4 )
      REVER_IPV4=${OCTET4}.${OCTET3}.${OCTET2}.${OCTET1}.in-addr.arpa
      echo "created reverse hostname $REVER_IPV4"

      # Set Hostname
      echo "setting hostname"
      hostnamectl set-hostname $LOCAL_NAME
      echo "hostname set"
      hostnamectl

      # Update /etc/hosts
      echo $LOCAL_IPV4 $LOCAL_NAME >> /etc/hosts

      # Update forward.json
      sed -i "s/YYYYY/$LOCAL_NAME/g" /root/.croninit/forward.json
      sed -i "s/ZZZZZ/$LOCAL_IPV4/g" /root/.croninit/forward.json

      # Create a forward private A record
      aws route53 change-resource-record-sets --hosted-zone-id ${forwardzoneid} --change-batch file:///root/.croninit/forward.json

      # Update reverse.json
      sed -i "s/YYYYY/$REVER_IPV4/g" /root/.croninit/reverse.json
      sed -i "s/ZZZZZ/$LOCAL_NAME/g" /root/.croninit/reverse.json

      # Create a reverse private PTR record
      aws route53 change-resource-record-sets --hosted-zone-id ${reversezoneid} --change-batch file:///root/.croninit/reverse.json

      # Add tags to this host
      aws ec2 create-tags --resources $( curl http://169.254.169.254/latest/meta-data/instance-id ) --tags Key=hostname,Value=$( echo $LOCAL_NAME ) --region us-east-1
      aws ec2 create-tags --resources $( curl http://169.254.169.254/latest/meta-data/instance-id ) --tags Key=ipv4,Value=$( echo $LOCAL_IPV4 ) --region us-east-1

      # Configure IPA Server
      if [[ "$is_ipa_server" == "yes" ]]
      then
        bash /root/.croninit/ipa/ipa_server_config.sh
      else
        echo "no ipa server"
      fi

      # Join IPA
      if [[ "$join_ipa" == "yes" ]]
      then
        ins_id=$( aws ec2 describe-instances --output text --query 'Reservations[].Instances[?not_null(Tags[?Key==`dsvc-ipamaster`].Value)] | [].[InstanceId]' --region us-east-1 )
        ipa_master=$( query_tags_external "hostname" $ins_id )
        /sbin/ipa-client-install --password 'bulkhostadd' --domain $( echo $domain ) --server $( echo $ipa_master ) --unattended
      else
        echo "no ipa"
      fi

      # Join CHEF
      if [[ "$join_chef" == "yes" ]]
      then
        echo "yes chef"
      else
        echo "no chef"
      fi

      # Prevent The Script From Running Again
      touch /root/.croninit/init.cfg
fi
