#!/bin/bash
##################################################
# Description: Installs, patches, and configures Wildfly 8.2.X in domain mode
#
# This script is designed to be called one directory higher than it is placed
#   in the repository.
# Author: Dustin Jefford
##################################################

source ./utilities
source ./parameters

print_divider
print_line "Starting Wildfly Installation in domain mode."
print_divider ; sleep 2

print_line "Start: Verifying directories." ; sleep 2

create_dir "${WILDFLY_HOME}"
create_dir "${LOGS_DIR}"

print_line "Finish: Verifying directories."

print_divider
print_line "Start: Unpacking Wildfly Media" ; sleep 2

mkdir -p ./working/media

extract_zip_media $MAIN_MEDIA ./working/media

# Move unpacked directory to WILDFLY_HOME
mv ./working/media/wildfly-8.2.1.Final/* $WILDFLY_HOME ; rc=$?
rc_eval "${rc}" "I: Successfully moved media to ${WILDFLY_HOME}." \
  "E: Failed to move media to ${WILDFLY_HOME}."

print_line "Finish: Unpacking Wildfly Media"

# If patch files are listed, then install patch
if [ ${#PATCH_LIST[@]} -gt 0 ]; then
  print_divider
  print_line "Start patching:"
  for patch in $PATCH_LIST ; do
    apply_patch $patch
  done
fi

print_divider
print_line "Start: Verifying and placing SSL keystore files." ; sleep 2

verify_loc "./ssl/keystore.jks"
#verify_loc "./ssl/truststore.jks"
verify_loc "./ssl/vault.jks"

cp -r "./ssl" "${WILDFLY_HOME}/" ; rc=$?
rc_eval "${rc}" "I: Successfully moved SSL keystores to ${WILDFLY_HOME}." \
  "E: Failed to move SSL keystores to ${WILDFLY_HOME}."

print_line "Finish: Placing SSL keystore files."

print_divider
print_line "Start: Gathering user input." ; sleep 2

read -p " Configure External LDAP for Administration? (y/n): " ldap_go ; print_line
read -p " Will this server be a domain slave server? (y/n): " slave ; print_line

read -s -p " Password for java keystore: "  java_jks_pass ; print_line
#read -s -p " Password for java truststore: " trust_jks_pass ; print_line
read -s -p " Password for vault keystore: " vault_jks_pass ; print_line

# Insert test values [Testing only]
#ldap_go="y"
#java_jks_pass="changeit"
#vault_jks_pass="changeit"

if [ "$ldap_go" == "y" ]; then
  read -s -p " Password for LDAP Bind account: " ldap_bind_pass ; print_line
#  ldap_bind_pass="wildfly"
  read -s -p " Password for LDAP secondary account: " ldap_secondary_pass ; print_line
else
  read -s -p " Password for local admin account: " local_admin_pass ; print_line
#  local_admin_pass="wildfly"
  if [ "$slave" == "y" ]; then
    read -p " Provide the secondary account user: " secondary_user ; print_line
    read -p " Provide the secondary account secret: " secondary_secret ; print_line
  fi
fi

print_line "Finish: Gathering user input."

print_divider
print_line "Start: Configuring Vault and store secrets." ; sleep 2

vault_add_item $vault_jks_pass javaKeystorePwd javaKeystore $java_jks_pass
#vault_add_item $vault_jks_pass trustKeystorePwd trustKeystore $trust_jks_pass

if [ "$ldap_go" == "y" ]; then
  vault_add_item $vault_jks_pass ldapAuthPwd ldapAuth $ldap_bind_pass
fi

print_line "Finished: Configuring Vault."

print_divider
print_line "Start: Capture masked vault password." ; sleep 2

# Grab masked password for vault for later use
vault_mask_pass=`vault_add_item $vault_jks_pass vaultAuthPwd vaultAuth $vault_jks_pass \
  | grep -o "\"MASK-.*\""`

# Remove beginning and trailing "
vault_mask_pass=$(sed -e 's/^"//' -e 's/"$//' <<<"$vault_mask_pass")

print_line "Finish: Captured masked vault password."

print_divider
print_line "Start: Replacing Variables in templates." ; sleep 2

# Set-up dynamic variables
short_hostname=$(sed -e 's/\..*//' <<<"$HOSTNAME")

# Check for optional IP, if none, try to determine IP address
if [ -z "${OPT_IP}" ]; then
  ip_addr=$(sed -e 's/ $//' <<<"$(hostname -I)")
else
  ip_addr="${OPT_IP}"
fi

if [ "$ldap_go" == "y" ]; then
  secondary_acct="$LDAP_SECONDARY_DN"
else
  secondary_acct="secondaryAcct"
fi

cp -r domain/templates ./working

for file in `ls ./working/templates`; do
  file_loc="./working/templates/$file"
  print_line "Updating ${file_loc}..."

  replace_var "{{WILDFLY_HOME}}" "$WILDFLY_HOME" "$file_loc"
  replace_var "{{JAVA_HOME}}" "$JAVA_HOME" "$file_loc"
  replace_var "{{LOGS_DIR}}" "$LOGS_DIR" "$file_loc"
  replace_var "{{HOSTNAME}}" "$HOSTNAME" "$file_loc"
  replace_var "{{SMTP_SERVER}}" "$SMTP_SERVER" "$file_loc"
  replace_var "{{WILDFLY_USER}}" "$WILDFLY_USER" "$file_loc"
  replace_var "{{ADMIN_GROUP}}" "$ADMIN_GROUP" "$file_loc"
  replace_var "{{MASTER_HOSTNAME}}" "$MASTER_HOSTNAME" "$file_loc"

  replace_var "{{SHORT_HOSTNAME}}" "$short_hostname" "$file_loc"
  replace_var "{{IP_ADDR}}" "$ip_addr" "$file_loc"

  replace_var "{{SECONDARY_ACCT}}" "$secondary_acct" "$file_loc"
  replace_var "{{SECONDARY_SECRET}}" "$secondary_secret" "$file_loc"

  replace_var "{{LDAP_URL}}" "$LDAP_URL" "$file_loc"
  replace_var "{{LDAP_ADMIN_GROUP}}" "$LDAP_ADMIN_GROUP" "$file_loc"
  replace_var "{{LDAP_ADMIN_GROUP_DN}}" "$LDAP_ADMIN_GROUP_DN" "$file_loc"
  replace_var "{{LDAP_BIND_DN}}" "$LDAP_BIND_DN" "$file_loc"
  replace_var "{{LDAP_NAME_ATTRIBUTE}}" "$LDAP_NAME_ATTRIBUTE" "$file_loc"
  replace_var "{{LDAP_BASE_DN}}" "$LDAP_BASE_DN" "$file_loc"
  replace_var "{{LDAP_SECONDARY_DN}}" "$secondary_acct" "$file_loc"

  replace_var "{{VAULT_ENC_FILE_DIR}}" "$VAULT_ENC_FILE_DIR" "$file_loc"
  replace_var "{{VAULT_SALT}}" "$VAULT_SALT" "$file_loc"
  replace_var "{{VAULT_ITERATION_COUNT}}" "$VAULT_ITERATION_COUNT" "$file_loc"
  replace_var "{{VAULT_ALIAS}}" "$VAULT_ALIAS" "$file_loc"
  replace_var "{{VAULT_KEYSTORE}}" "$VAULT_KEYSTORE" "$file_loc"

  replace_var "{{VAULT_MASKED_PASSWORD}}" "$vault_mask_pass" "$file_loc"

done

print_line "Finish: Variable replacement"

print_divider
print_line "Start: Placing start-up scripts" ; sleep 2

mkdir -p ${WILDFLY_HOME}/conf/domain
mkdir -p ${WILDFLY_HOME}/conf/scripts

cp ./working/templates/wildfly.conf ${WILDFLY_HOME}/conf/domain
cp ./working/templates/wildfly-init.sh ${WILDFLY_HOME}/conf/scripts
cp ./working/templates/wildfly-domain.service ${WILDFLY_HOME}/conf/scripts

print_line "Finish: Placing start-up scripts"

print_divider
print_line "Start: Updating permissions." ; sleep 2

mkdir -p ${WILDFLY_HOME}/conf/crontabs

cp ./working/templates/wildflyPerms.sh ${WILDFLY_HOME}/conf/crontabs/

${WILDFLY_HOME}/conf/crontabs/wildflyPerms.sh ; rc=$?

rc_eval "${rc}" "I: Successfully updated permissions." \
  "E: Permissions updates failed."

print_line "Finish: Updating permissions"

print_divider
print_line "Start: Starting wildfly." ; sleep 2

start_stop_domain start
print_line "Waiting for start-up to complete." ; sleep 10

print_line "Finish: Starting wildfly."

print_divider
print_line "Start: Configuration of domain install"

execute_cli_command ${ip_addr} "/server-group=main-server-group:stop-servers"
execute_cli_command ${ip_addr} "/server-group=other-server-group:stop-servers"
execute_cli_script ${ip_addr} ./working/templates/domain-general.cli

print_line "Finish: Configuration of domain install"

if [ "$ldap_go" == "y" ]; then
  print_line "Start: External LDAP configuration."
  execute_cli_script ${ip_addr} ./working/templates/domain-ldap.cli
  print_line "Finish: External LDAP configuration."
else
  print_line "Start: Configure local users."
  add_local_user admin "$local_admin_pass"
  #add_local_user $secondary_acct "$local_secondary_pass"
  print_line "Finish: Configure loacl users."
fi

execute_cli_command ${ip_addr} "/host=master:write-attribute(name=name,value=\"$short_hostname\")"

print_line "Finish: Configuration of domain install"
print_divider

print_line "Start: Stopping wildfly." ; sleep 2

start_stop_domain stop

print_line "Placing custom jboss-cli.xml script."
cp ./working/templates/jboss-cli.xml ${WILDFLY_HOME}/bin/

print_line "Finish: Stopping wildfly."

print_divider

print_line "Wildfly Installation completed in domain mode."

print_divider
print_divider
