# Copyright 2013 42Lines, Inc.
# Original Author: Jim Browne
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

####
# Set AWS-related environment variables
# Globals: none
# Arguments: $1 account; $2 accessKey; $3 secretAccessKey; $4 (optional) token
# Returns: none
####
function _ec2setvars()
{
    # Dropped support for credential file; anything other than boto using it?
    #export AWS_CREDENTIAL_FILE=${basedir}/aws.credentials.${account}
    
    # ec2 cli environment variables
    export AWS_ACCESS_KEY=$2
    export AWS_SECRET_KEY=$3
    
    # boto and aws-cli environment variables
    export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY}
    export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_KEY}
    
    if [[ -n "$4" ]]; then
	# aws-cli environment variable
	export AWS_SECURITY_TOKEN=$4
	# ec2 cli environment variable
	export AWS_DELEGATION_TOKEN=$4
    else
	unset AWS_SECURITY_TOKEN
	unset AWS_DELEGATION_TOKEN
    fi
}

####
# Check if local files caching AWS STS credntials are present and not expired
# Globals: none
# Arguments: $1 basedir; $2 account
# Returns: true if the cache is valid and current; false if not
####
function _ec2checkcache()
{
    local filename=.cache.$2.expiration
    local file=$1/${filename}
    local token=$1/.cache.$2.session_token

    if [[ ! -f "${file}" ]]; then
	echo "Cache not present for account ${2}"
	return 1
    fi

    # The expiration file contains an integer specifying the number of
    # minutes the temporary credential is valid
    local expiration
    expiration=$(cat ${file})

    # See if the duration since the modification time (when the
    # credential was recorded) is greater than the duration (lifetime)
    # of the temporary credential
    if [[ $(find "$1" -name "${filename}" -mmin -"${expiration}" \
	| wc -l) -gt 0 ]]; then
	echo "Cache is valid for account ${2}"
	return 0
    else
	# If the cache is expired, remove the session_token file
	[[ -f "${token}" ]] && rm -f "${token}"
	echo "Cache invalid or not present for account ${2}"
	return 1
    fi
}

####
# Set AWS-related environment variables based on account selected and possible
# presence of cached STS credentials
#
# Globals: none
# Arguments: $1 desired account
# Returns: none
####
function ec2switch()
{

    local basedir=${HOME}/aws-creds

    if [[ ! -d "${basedir}" ]]; then
	echo "No creds directory? ${basedir}"
    elif [[ -z "$1" ]]; then
	echo -n "Possible accounts: "
	ls ${basedir}/*.access_key \
	    | sed -e 's/.*aws-creds\/\(.*\).access_key/\1/' \
	    | xargs -I{} echo -n "{} "
	echo
    else
	local account=$(echo $1 | tr '[:upper:]' '[:lower:]')
	local canary=${basedir}/${account}.access_key

	if [[ ! -f "${canary}" ]]; then
	    echo "Didn't find canary ${canary} for account ${account}"
	    # exiting here would exit the parent shell
	else
	    local filebase=${basedir}/

	    # See if there are cached temporary credentials
	    local cached=
	    if _ec2checkcache ${basedir} ${account}; then
		cached=true
	    fi

	    if [[ -n "${cached}" ]]; then
		filebase=${filebase}.cache.
	    fi

	    filebase=${filebase}${account}.

	    local access
	    access=$(cat ${filebase}access_key)
	    local secret
	    secret=$(cat ${filebase}secret_key)

	    # Ensure AWS_SECURITY_TOKEN is cleared if not valid
	    local token=''
	    if [[ -n "${cached}" ]] && [[ -f "${filebase}session_token" ]]; then
		token=$(cat ${filebase}session_token)
	    fi

	    _ec2setvars ${account} ${access} ${secret} ${token}

	    if [[ -n "${cached}" ]]; then
		export MY_AWS_SET_FOR="$1-MFA-STS"
	    else
		export MY_AWS_SET_FOR=$1
	    fi

	    echo "Set keys for ${MY_AWS_SET_FOR} AWS account"

	    # aws-cli specific environment variable
	    if [[ -z "${AWS_DEFAULT_REGION}" ]]; then
		export AWS_DEFAULT_REGION='us-east-1'
	    fi
	fi
    fi
}

export -f ec2switch

####
# Show state of AWS-related environment variables
#
# Globals: none
# Arguments: none
# Returns: none
####
function ec2now()
{
    if [[ -z "${MY_AWS_SET_FOR}" ]]; then
	echo "No keys set"
    else
	echo "Keys set for ${MY_AWS_SET_FOR} AWS account"
    fi

    if [[ -n "${AWS_DEFAULT_REGION}" ]]; then
	echo "Region is ${AWS_DEFAULT_REGION}"
    fi
}

export -f ec2now

####
# Attempt to acquire temporary STS credentials in the currently selected
# AWS account, then set environment variables based on the newly cached
# credentials.  The IAM user name may be specified in aws-creds/account.user
# and will default to the current unix user name.
#
# Globals: none
# Arguments: none
# Returns: none
####
function ec2mfa()
{
    if [[ -z "${MY_AWS_SET_FOR}" ]]; then
	echo "No keys set"
    else
	# run ec2switch to check cache expiration
	ec2switch ${MY_AWS_SET_FOR%-MFA-STS}

	if [[ ${MY_AWS_SET_FOR} =~ MFA-STS ]]; then
	    echo "MFA STS token already cached"
	else
	    local iamuser=${USER}
	    if [[ -f ${HOME}/aws-creds/${MY_AWS_SET_FOR}.user ]] ; then
		iamuser=$(cat ${HOME}/aws-creds/${MY_AWS_SET_FOR}.user)
	    fi
	    read -e -p "Enter token for user ${iamuser}: " token
	    # Create credentials good for two hours (7200 minutes)
	    generate-sts-mfa-token --account ${MY_AWS_SET_FOR} --user=${iamuser} --token=${token} --duration 14400 --cachefiles
	    if [ $? -ne 0 ]; then
		echo "Failed to set MFA token"
	    else
		ec2switch ${MY_AWS_SET_FOR}
	    fi
	fi
    fi
}

export -f ec2mfa
