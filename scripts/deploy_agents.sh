#!/bin/sh
set +x
sshpass -p $CD_PASS ssh -q $CD_USER@$HOST /bin/bash <<EOF
# become wwwadm
sudo -su wwwadm
# set temp directory
TMP_DIR="$TMP_DIR"
echo "Temp directory: \$TMP_DIR"
# create base and agent root
mkdir -p $BIN_DIR
mkdir -p $AGENT_ROOT
chmod 755 $BIN_DIR
chmod 775 $AGENT_ROOT
# get agents
cd \$TMP_DIR
echo "Working directory: \$(pwd)"
AGENTS=\$(ls -d output/fluent-bit.*)
# create agent and service directories
for agent in \${AGENTS[@]} ; do
    AGENT=\$(basename \$agent)
    AGENT_HOME=$AGENT_ROOT/\$AGENT
    mkdir -p \$AGENT_HOME/{bin,conf,db,lib,logs,scripts}
    mkdir -p $S6_SERVICE_HOME/\$AGENT
    chmod 775 $S6_SERVICE_HOME/\$AGENT
done
# download dependencies
/bin/curl -x $HTTP_PROXY -sSL "https://releases.hashicorp.com/vault/${VAULT_RELEASE}/vault_${VAULT_RELEASE}_linux_amd64.zip" -o "/tmp/vault_${VAULT_RELEASE}_linux_amd64.zip"
/bin/curl -x $HTTP_PROXY -sSL "https://releases.hashicorp.com/envconsul/${ENVCONSUL_RELEASE}/envconsul_${ENVCONSUL_RELEASE}_linux_amd64.zip" -o "/tmp/envconsul_${ENVCONSUL_RELEASE}_linux_amd64.zip"
/bin/curl -x $HTTP_PROXY -sSL "https://github.com/stedolan/jq/releases/download/jq-${JQ_RELEASE}/jq-linux64" -o $BIN_DIR/jq
/bin/curl -u $CI_USER:$CI_PASS -sSL "http://bwa.nrs.gov.bc.ca/int/artifactory/ext-binaries-local/fluent/fluent-bit/${FLUENTBIT_RELEASE}/fluent-bit.tar.gz" -o /tmp/fluent-bit.tar.gz
# set jq as executable
chmod 755 $BIN_DIR/jq
# extract bin and lib
cd
tar -zxvf /tmp/fluent-bit.tar.gz --strip-components=1
# move dependencies to agent directories
for agent in \${AGENTS[@]} ; do
    AGENT=\$(basename \$agent)
    AGENT_HOME=$AGENT_ROOT/\$AGENT
    cp fluent-bit \$AGENT_HOME/bin
    cp libpq.so.5 \$AGENT_HOME/lib
done
# unzip vault and envconsul
unzip -o /tmp/vault_1.7.1_linux_amd64.zip -d $BIN_DIR
unzip -o /tmp/envconsul_0.11.0_linux_amd64.zip -d $BIN_DIR
# deploy config
cd \$TMP_DIR
echo "Working directory: \$(pwd)"

for agent in \${AGENTS[@]} ; do
    AGENT=\$(basename \$agent)
    AGENT_HOME=$AGENT_ROOT/\$AGENT
    cp -R output/\$AGENT/* \$AGENT_HOME/conf
    sed -e "s,\\\$HTTP_PROXY,\$HTTP_PROXY,g" -e "s,{{ apm_agent_home }},\$AGENT_HOME,g" fluent-bit.hcl > \$AGENT_HOME/conf/fluent-bit.hcl
    cp fluentbitw \$AGENT_HOME/bin
    sed "s,{{ apm_agent_home }},\$AGENT_HOME,g" fluent-bit-logrotate.conf > \$AGENT_HOME/\$AGENT-logrotate.conf
    ln -sfn \$AGENT_HOME/bin/fluentbitw $S6_SERVICE_HOME/\$AGENT/run
    # TODO: revoke previous token
    # deploy new token to .env file
    sed 's/VAULT_TOKEN=.*/VAULT_TOKEN="${APP_TOKEN}"/g' .env > \$AGENT_HOME/bin/.env
    chmod 775 \$AGENT_HOME/bin/fluentbitw \$AGENT_HOME/db \$AGENT_HOME/logs
done
EOF