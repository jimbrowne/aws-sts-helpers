Tools for working with AWS temporary and multi-factor authentication credentials
--------------------------------------------------------------------------------

When using an IAM user that has MFA enabled, temporary credentials are issued
using the [GetSessionToken](http://docs.aws.amazon.com/STS/latest/APIReference/API_GetSessionToken.html)
API call.  We've written a tool to make the GetSessionToken call and manage environment variables
to make working with temporary credentials more convenient.  We've also included a tool that scripts
can use to receive temporary credentials from an [AssumeRole](http://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
call.

Requirements
------------

[Boto](https://github.com/boto/boto) version 2.22.1 or greater

Credential directory
--------------------

The tools assume you have a credential directory in ```{$HOME}/aws-creds```:

    jbrowne@foo:~$ ls -l ~/aws-creds/ | grep -v .cache
    work.access_key
    work.secret_key
    personal.access_key
    personal.secret_key

These are IAM role user keys that have no permissions on their own; rather they are 
only useful once one has authenticated with MFA.  This is enforced by including:

    "Condition":{
            "Null":{"aws:MultiFactorAuthAge":"false"}
    }

in the IAM permissions.

The credential directory is also used to cache credentials received from GetSessionToken.

Account file
------------

The tools assume there is a JSON file with account information.  The location can
be overridden by passing ```--config```.  Example file:

    {
        "personal": "arn:aws:iam::987654321012:",
        "work":  "arn:aws:iam::012123456789:"
    }

The numbers are the account IDs.  These can be found on the account summary page.

Setting credentials
-------------------
"Setting credentials" means to set the appropriate environment variables, specifically:

* ec2 cli environment variables                                             

        AWS_ACCESS_KEY
        AWS_SECRET_KEY
        AWS_DELEGATION_TOKEN

* boto and aws-cli environment variables                                    

        AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY
        AWS_SECURITY_TOKEN (not yet suported for boto, see Requirements section)

*Note*: boto doesn't yet support ```AWS_SECURITY_TOKEN```

Ensure ```ec2switch.sh``` is in ```/etc/profile.d``` or:

       source ec2switch.sh


1. To start, no keys are set:

        jbrowne@foo:~$ ec2now
        No keys set

2. Let's see what accounts are available:

        jbrowne@foo:~$ ec2switch 
        Possible accounts: work personal 

3. Let's switch to the IAM credentials for ```${USER}```, account personal

        jbrowne@foo:~$ ec2switch personal
        Cache invalid or not present for account personal
        Set keys for personal AWS account

4. We can see that the credentials are set:

        jbrowne@foo:~$ ec2now
        Keys set for personal AWS account
        Region is us-east-1

5. Let's escalate to MFA confirmed credentials:

        jbrowne@foo:~$ ec2mfa
        Enter token for user jbrowne: 281823
        Cache is valid for account personal
        Set keys for personal-MFA-STS AWS account

6. ```ec2now``` reflects the presence of MFA credentials:

        jbrowne@foo:~$ ec2now
        Keys set for personal-MFA-STS AWS account
        Region is us-east-1

7. Switch to the work account, no cache present, so no MFA creds:

        jbrowne@foo:~$ ec2switch work
        Cache not present for account work
        Set keys for work AWS account

8. Switch back to the personal account, MFA credentials are cached:

        jbrowne@foo:~$ ec2switch personal
        Cache is valid for account personal
        Set keys for personal-MFA-STS AWS account

Generating AssumeRole temporary credentials for scripts
-------------------------------------------------------

```generate-sts-role-token``` calls AssumeRole to generate temporary authentication
credentials.  The default is to emit JSON (for use by other scripts), but it can also
emit copy/paste-able SHELL environment variable statements.

*Note*: Currently --token has to be passed as boto does not (yet) support the
```AWS_SECURITY_TOKEN``` environment variable.


    jbrowne@foo:~$ generate-sts-role-token --account work --role work-temporary-escalation --token ${AWS_SECURITY_TOKEN} 
    {
        "access_key": "ASIAABCDEFGHIJK3ZP5A",
        "expiration": "2013-12-20T00:59:32Z",
        "secret_key": "kl0y+01234567897cmAzxABCDEFGHIJ6a7pTXQde",
        "session_token": "AQoDYXdzREALLYLONGTOKENHERE=="
    }
