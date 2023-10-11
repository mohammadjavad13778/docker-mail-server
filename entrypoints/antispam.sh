#!/bin/bash
# Author: Zhang Huangbin <zhb@iredmail.org>

#
# This file is managed by iRedMail Team <support@iredmail.org> with Ansible,
# please do __NOT__ modify it manually.
#

. /docker/entrypoints/functions.sh

AMAVISD_CONF="/etc/amavis/conf.d/50-user"
AMAVISD_CUSTOM_CONF_DIR="/opt/iredmail/custom/amavisd"

AMAVISD_SPOOL_DIR="/var/spool/amavisd"
AMAVISD_TEMP_DIR="/var/spool/amavisd/tmp"
AMAVISD_QUARANTINE_DIR="/var/spool/amavisd/quarantine"
AMAVISD_DB_DIR="/var/spool/amavisd/db"
AMAVISD_VAR_DIR="/var/spool/amavisd/var"

AMAVISD_DKIM_DIR="/opt/iredmail/custom/amavisd/dkim"
DKIM_KEY="${AMAVISD_DKIM_DIR}/${FIRST_MAIL_DOMAIN}.pem"

# SpamAssassin
SPAMASSASSIN_CONF_LOCAL="/etc/spamassassin/local.cf"
SPAMASSASSIN_PLUGIN_RAZOR_CONF="/etc/spamassassin/razor.conf"
SPAMASSASSIN_CUSTOM_CONF_DIR="/opt/iredmail/custom/spamassassin"
SPAMASSASSIN_CUSTOM_CONF="/opt/iredmail/custom/spamassassin/custom.cf"

# ClamAV
CLAMAV_DB_DIR="/var/lib/clamav"

chown ${SYS_USER_ROOT}:${SYS_GROUP_AMAVISD} ${AMAVISD_CONF}

############### Permission Problem ###############
AMAVISD_CONF_DIR="/etc/amavis"
chmod 755 -R ${AMAVISD_CONF_DIR}
SPAMASSASSIN_CONF_DIR="/etc/spamassassin"
chmod 755 -R ${SPAMASSASSIN_CONF_DIR}

# For SECURE PASSWORD
chmod 750 -R ${AMAVISD_CONF} ${SPAMASSASSIN_CONF_LOCAL}
##################################################

for d in \
    ${AMAVISD_SPOOL_DIR} \
    ${AMAVISD_TEMP_DIR} \
    ${AMAVISD_QUARANTINE_DIR} \
    ${AMAVISD_DB_DIR} \
    ${AMAVISD_VAR_DIR}; do
    [[ -d ${d} ]] || mkdir -p ${d}
    chown ${SYS_USER_AMAVISD}:${SYS_GROUP_AMAVISD} ${d}
    ##### permission problem #####
    #chmod 0770 ${d}
    chmod 0775 ${d}
    ##############################
done

# Amavisd
install -d -o ${SYS_USER_ROOT} -g ${SYS_GROUP_ROOT} -m 0755 ${AMAVISD_CUSTOM_CONF_DIR}
install -d -o ${SYS_USER_AMAVISD} -g ${SYS_GROUP_AMAVISD} -m 0770 ${AMAVISD_DKIM_DIR}
# ClamAV
install -d -o ${SYS_USER_CLAMAV} -g ${SYS_GROUP_CLAMAV} -m 0755 ${CLAMAV_DB_DIR}
# SpamAssassin
install -d -o ${SYS_USER_ROOT} -g ${SYS_GROUP_ROOT} -m 0755 ${SPAMASSASSIN_CUSTOM_CONF_DIR}
touch_files ${SYS_USER_AMAVISD} ${SYS_GROUP_AMAVISD} 0640 ${SPAMASSASSIN_CONF_LOCAL} ${SPAMASSASSIN_PLUGIN_RAZOR_CONF} ${SPAMASSASSIN_CUSTOM_CONF}

# Assign clamav daemon user to Amavisd group, so that it has permission to scan message.
usermod -G ${SYS_GROUP_AMAVISD} ${SYS_USER_CLAMAV}

# Generate DKIM key for first mail domain.
[[ -f ${DKIM_KEY} ]] || /usr/sbin/amavisd-new genrsa ${DKIM_KEY} 1024
touch_files ${SYS_USER_AMAVISD} ${SYS_GROUP_AMAVISD} 0770 ${DKIM_KEY}

# Update parameters.
${CMD_SED} "s#PH_HOSTNAME#${HOSTNAME}#g" ${AMAVISD_CONF}
${CMD_SED} "s#PH_FIRST_MAIL_DOMAIN#${FIRST_MAIL_DOMAIN}#g" ${AMAVISD_CONF}

#################Always update SQL password#################
_amavis_dbi_string="DBI:mysql:database=amavisd;host=PH_SQL_SERVER_ADDRESS;port=PH_SQL_SERVER_PORT', 'amavisd', '${AMAVISD_DB_PASSWORD}']);"
${CMD_SED} "s#DBI:mysql:database=amavisd.*#${_amavis_dbi_string}#g" ${AMAVISD_CONF}

${CMD_SED} "s#bayes_sql_password.*#bayes_sql_password ${SA_BAYES_DB_PASSWORD}#g" ${SPAMASSASSIN_CONF_LOCAL}
############################################################

${CMD_SED} "s#PH_SQL_SERVER_ADDRESS#${SQL_SERVER_ADDRESS}#g" ${AMAVISD_CONF} ${SPAMASSASSIN_CONF_LOCAL}
${CMD_SED} "s#PH_SQL_SERVER_PORT#${SQL_SERVER_PORT}#g" ${AMAVISD_CONF} ${SPAMASSASSIN_CONF_LOCAL}

# Run `sa-update` if no rules yet.
LOG "Run 'sa-update' (required by Amavisd)."
sa-update -v

if [[ ! -f "${CLAMAV_DB_DIR}/main.cvd" ]] && [[ ! -f "${CLAMAV_DB_DIR}/bytecode.cvd" ]]; then
    LOG "Run 'freshclam' (required by ClamAV)."
    freshclam
fi
