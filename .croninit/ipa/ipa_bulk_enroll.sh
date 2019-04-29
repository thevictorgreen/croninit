#!/bin/bash


# Query Tags
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

DOMAIN=$( query_tags domain )
read -p "enter client prefix: " PREFIX
read -p "enter starting index: " START
read -p "enter ending index: " END

kinit admin
for host in $(eval echo "{$START..$END}")
do
        echo ${PREFIX}${host}.${DOMAIN}
        ipa host-add ${PREFIX}${host}.${DOMAIN} --password=bulkhostadd --force
done
