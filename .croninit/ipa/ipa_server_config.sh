#!/bin/bash


# Log Output To A File
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/root/.croninit/ipa_server.out 2>&1


#Query Tags
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

forwardzoneid=$( query_tags forwardzoneid )

# Grab Hostname
LOCAL_NAME=$( hostname )

# Grab private IP Address
LOCAL_IPV4=$( curl http://169.254.169.254/latest/meta-data/local-ipv4 )

# Set Domain
DP1=$( echo $LOCAL_NAME | cut -d. -f2  )
DP2=$( echo $LOCAL_NAME | cut -d. -f3  )
DOMAIN=${DP1}.${DP2}
REALM=$( printf '%s\n' "$DOMAIN" | awk '{ print toupper($0) }' )

# Install IPA Server
/sbin/ipa-server-install --realm=$REALM --domain=$DOMAIN --hostname=$LOCAL_NAME --ip-address=$LOCAL_IPV4 --ds-password=admin123 --admin-password=admin123 --mkhomedir --unattended

# Create IPA Related DNS Records
R1KEY=_kerberos-master._tcp.${DOMAIN}
R1VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R1KEY/g" /root/.croninit/ipa/r1.json
sed -i "s/ZZZZZ/$R1VAL/g" /root/.croninit/ipa/r1.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r1.json

R2KEY=_kerberos-master._udp.${DOMAIN}
R2VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R2KEY/g" /root/.croninit/ipa/r2.json
sed -i "s/ZZZZZ/$R2VAL/g" /root/.croninit/ipa/r2.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r2.json

R3KEY=_kerberos._tcp.${DOMAIN}
R3VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R3KEY/g" /root/.croninit/ipa/r3.json
sed -i "s/ZZZZZ/$R3VAL/g" /root/.croninit/ipa/r3.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r3.json

R4KEY=_kerberos._udp.${DOMAIN}
R4VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R4KEY/g" /root/.croninit/ipa/r4.json
sed -i "s/ZZZZZ/$R4VAL/g" /root/.croninit/ipa/r4.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r4.json

R5KEY=_kerberos.${DOMAIN}
R5VAL=${REALM}
sed -i "s/YYYYY/$R5KEY/g" /root/.croninit/ipa/r5.json
sed -i "s/ZZZZZ/$R5VAL/g" /root/.croninit/ipa/r5.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r5.json

R6KEY=_kpasswd._tcp.${DOMAIN}
R6VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R6KEY/g" /root/.croninit/ipa/r6.json
sed -i "s/ZZZZZ/$R6VAL/g" /root/.croninit/ipa/r6.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r6.json

R7KEY=_kpasswd._udp.${DOMAIN}
R7VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R7KEY/g" /root/.croninit/ipa/r7.json
sed -i "s/ZZZZZ/$R7VAL/g" /root/.croninit/ipa/r7.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r7.json

R8KEY=_ldap._tcp.${DOMAIN}
R8VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R8KEY/g" /root/.croninit/ipa/r8.json
sed -i "s/ZZZZZ/$R8VAL/g" /root/.croninit/ipa/r8.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r8.json

R9KEY=_ntp._udp.${DOMAIN}
R9VAL=${LOCAL_NAME}
sed -i "s/YYYYY/$R9KEY/g" /root/.croninit/ipa/r9.json
sed -i "s/ZZZZZ/$R9VAL/g" /root/.croninit/ipa/r9.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r9.json

RTKEY=ipa-ca.${DOMAIN}
RTVAL=${LOCAL_IPV4}
sed -i "s/YYYYY/$RTKEY/g" /root/.croninit/ipa/r10.json
sed -i "s/ZZZZZ/$RTVAL/g" /root/.croninit/ipa/r10.json
aws route53 change-resource-record-sets --hosted-zone-id $( echo $forwardzoneid ) --change-batch file:///root/.croninit/ipa/r10.json

# Add Tags for Service Discovery
aws ec2 create-tags --resources $( curl http://169.254.169.254/latest/meta-data/instance-id ) --tags Key=dsvc-ipamaster,Value=$( echo $LOCAL_NAME ) --region us-east-1
