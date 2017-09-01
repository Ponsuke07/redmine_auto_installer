#!/bin/bash

function usage() {
    name=$(basename $0)
    cat << EOS
Usage: $name [-a accessdir <dir>] [-D redmine-dir <dir>] [-h help] [-H host <host>] [-p user-password <pwd>]
                  [-P root-passowrd <pwd>] [-u user-name <name>] [-v verbose] [-V redmin-version <version>]
EOS
exit 0
}

redmine_ver="3.2.0"
wwwroot="/var/www/html"

verbose_flg=0
redminedir="redmine"
accessdir="rm"
uname="root"
upass=""
password=""
host="localhost"

while getopts a:D:hH:p:P:u:vV: OPT
do
    case $OPT in
        a) accessdir="$OPTARG"
           ;;
        D) redminedir="$OPTARG"
           ;;
        h) usage
           ;;
        H) host="$OPTARG"
           ;;
        p) upass="$OPTARG"
           ;;
        P) password="$OPTARG"
           ;;
        u) uname="$OPTARG"
           ;;
        v) verbose_flg=1
           ;;
        V) redmine_ver="$OPTARG"
           ;;
    esac
done

function vecho() {
    if [ $verbose_flg -eq 1 ]
    then
        echo $1
    fi
    return 0
}

function check_result() {
    if [ "$?" -ne "0" ] ;then
        echo "Error: Faild to ${1:-somewhere}." >&2
        exit 1
    else
        vecho "done."
    fi
}

procName="Download Redmine"
vecho "$procName..."
dwnFile="${wwwroot}/redmine.tar.gz"
wget "http://www.redmine.org/releases/redmine-${redmine_ver}.tar.gz" -O "${dwnFile}"
check_result "$procName"


procName="Expand downloaded tar.gz"
vecho "$procName..."
if [ "$verbose_flg" -eq 1 ]
then
    tar zxvf "${wwwroot}/redmine.tar.gz" -C "${wwwroot}"
else
    tar zxf "${wwwroot}/redmine.tar.gz" -C "${wwwroot}"
fi
check_result "$procName"


procName="Rename redmine directory"
vecho "$procName..."
mv ${wwwroot}/redmine-${redmine_ver}/ ${wwwroot}/${redminedir}/
check_result "$procName"
procName="Create database"
vecho "$procName..."
mysql -u root --password="${password}" -e "create database if not exists redmine_${uname} character set utf8;"
check_result "$procName"
mysql -u root --password="${password}" -e "grant all on redmine_${uname}.* to '${uname}'@'localhost' identified by '${upass}';"
check_result "$procName"


procName="Config redmine database"
vecho "$procName..."
vecho "Change directory into redmine"
cd redmine
cat <<EOF > config/database.yml
production:
  adapter: mysql2
  database: redmine_${uname}
  host: ${host}
  usernae: ${uname}
EOF
if [ ! $upass == "" ]
then
    cat password: ${upass} >> config/database.yml
fi
cat <<EOF >> config/database.yml
  encoding: utf8
EOF
check_result "$procName"


procName="Install bundler from gem"
vecho "$procName..."
gem install bundler
check_result "$procName"


procName="Resolve dependency with bundler"
vecho "$procName..."
bundle install --without development test postgresql sqlite --path vandor/bundle
check_result "$procName"


procName="Generate session-store secret key"
vecho "$procName..."
bundle exec rake generate_secret_token
check_result "$procName"


procName="Create table"
vecho "$procName..."
RAILS_ENV=production bundle exec rake db:migrate
check_result "$procName"


procName="Sign in Default data"
vecho "$procName..."
RAILS_ENV=production REDMINE_LANG=ja bundle exec rake redmine:load_default_data
check_result "$procName"


chown -R ${uname}:${uname} files log tmp public/plugin_assets
check_result "$procName"
chmod -R 755 files log tmp public/plugin_assets
check_result "$procName"


procName="Install Passenger"
vecho "$procName..."
gem install passenger --no-rdoc --no-ri
passenger-install-apache2-module --auto
check_result "$procName"


procName="Setting apache"
vecho "$procName..."
cat <<EOF > /etc/httpd/conf.d/redmine.conf
<Directory "${wwwroot}/redmine/public">
Require all granted
</Directory>
EOF
bash -c "passenger-install-apache2-module --snippet >> /etc/httpd/conf.d/redmine.conf"
check_result "$procName"

chown -R apache:apache ${wwwroot}/redmine
ln -s ${wwwroot}/redmine/public ${wwwroot}/${accessdir}
bash -c "echo 'RackBaseURI /${accessdir}' >> -a /etc/httpd/conf.d/redmine.conf"

procName="apache configtest"
vecho "$procName..."
service httpd configtest
check_result "$procName"

service httpd graceful

